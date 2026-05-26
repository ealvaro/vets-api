# frozen_string_literal: true

module UnifiedHealthData
  module Adapters
    # Extracts submission metadata from contained FHIR Task resources on MedicationRequests.
    # Handles both refill (intent='order') and renewal (intent='proposal') Tasks.
    #
    # This module is designed to be included in OracleHealthPrescriptionAdapter
    # and depends on methods from FhirHelpers:
    # - parse_date_or_epoch(date_string)
    module OracleHealthTaskHelper
      TASK_TYPE_EXTENSION_URL = 'http://va.gov/mhv/rx/task-type'

      # Extracts refill submission metadata from Task resources during prescription parsing.
      # Sets refill_submit_date based on successful refill requests.
      #
      # Conditions for a valid submitted refill:
      # 1. Task with intent='order', status='requested', and matching focus.reference exists
      # 2. No MedicationDispense with whenPrepared or whenHandedOver date after Task.executionPeriod.start
      #
      # @param resource [Hash] FHIR MedicationRequest resource
      # @param dispenses_data [Array<Hash>] Array of dispense data for checking subsequent dispenses
      # @return [Hash] Hash containing refill_submit_date if applicable
      def extract_refill_submission_metadata_from_tasks(resource, dispenses_data = [])
        most_recent_task = most_recent_contained_task(resource, intent: 'order')
        return {} unless most_recent_task

        task_submit_date = most_recent_task.dig('executionPeriod', 'start')
        return {} unless valid_task_date?(task_submit_date)
        return {} if subsequent_dispense?(task_submit_date, dispenses_data)

        { refill_submit_date: task_submit_date }
      end

      # Extracts renewal submission metadata from Task resources during prescription parsing.
      # Sets renewal_submitted_timestamp based on the most recent renewal request.
      #
      # Conditions for a valid renewal task:
      # 1. Task with intent='proposal', status='requested', and matching focus.reference exists
      # 2. Task meta extension 'http://va.gov/mhv/rx/task-type' equals 'renewal' (if present)
      #
      # @param resource [Hash] FHIR MedicationRequest resource
      # @return [Hash] Hash containing renewal_submitted_timestamp (epoch millis) if applicable
      def extract_renewal_submission_metadata_from_tasks(resource)
        most_recent_task = most_recent_contained_task(resource, intent: 'proposal') { |t| renewal_task_type?(t) }
        return {} unless most_recent_task

        task_submit_date = most_recent_task.dig('executionPeriod', 'start')
        return {} unless valid_task_date?(task_submit_date)

        parsed_date = parse_date_or_epoch(task_submit_date)
        { renewal_submitted_timestamp: (parsed_date.to_i * 1000) + (parsed_date.nsec / 1_000_000) }
      end

      private

      # Finds the most recent contained Task matching the given intent and optional block filter.
      #
      # @param resource [Hash] FHIR MedicationRequest resource
      # @param intent [String] Task intent to filter by ('order' or 'proposal')
      # @yield [Hash] Optional additional filter block
      # @return [Hash, nil] Most recent matching Task or nil
      def most_recent_contained_task(resource, intent:)
        contained_resources = resource['contained'] || []
        medication_request_id = resource['id']

        matching_tasks = contained_resources.select do |c|
          c.is_a?(Hash) &&
            c['resourceType'] == 'Task' &&
            c['intent'] == intent &&
            c['status'] == 'requested' &&
            task_references_medication_request?(c, medication_request_id) &&
            (!block_given? || yield(c))
        end

        return nil if matching_tasks.empty?

        matching_tasks.max_by { |task| parse_date_or_epoch(task.dig('executionPeriod', 'start')) }
      end

      # Validates that a task date string is present and parseable.
      def valid_task_date?(date_string)
        return false unless date_string

        parse_date_or_epoch(date_string) != Time.zone.at(0)
      end

      # Validates that Task.focus.reference matches the parent MedicationRequest.id
      def task_references_medication_request?(task, medication_request_id)
        return false unless medication_request_id

        focus_reference = task.dig('focus', 'reference')
        return false unless focus_reference

        focus_reference == "MedicationRequest/#{medication_request_id}"
      end

      # Checks if there's a completed MedicationDispense with whenPrepared or whenHandedOver
      # date after the Task.executionPeriod.start.
      # Only completed dispenses count as fulfillment — in-progress dispenses indicate
      # the pharmacy is still processing the refill, so the submission date should remain.
      def subsequent_dispense?(task_start_time, dispenses_data)
        return false unless dispenses_data.present? && task_start_time.present?

        task_time = parse_date_or_epoch(task_start_time)

        dispenses_data.any? do |dispense|
          next false unless dispense[:status] == 'completed'

          (dispense[:when_prepared].present? && parse_date_or_epoch(dispense[:when_prepared]) > task_time) ||
            (dispense[:when_handed_over].present? && parse_date_or_epoch(dispense[:when_handed_over]) > task_time)
        end
      end

      # Checks if a Task is a renewal task based on the task-type meta extension.
      # Returns true if no task-type extension is present (assumes renewal when intent='proposal').
      def renewal_task_type?(task)
        extensions = task.dig('meta', 'extension') || []
        task_type_ext = extensions.find { |e| e['url'] == TASK_TYPE_EXTENSION_URL }
        return true unless task_type_ext

        task_type_ext['valueString'] == 'renewal'
      end
    end
  end
end
