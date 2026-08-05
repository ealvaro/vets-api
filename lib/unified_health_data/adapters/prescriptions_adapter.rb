# frozen_string_literal: true

require_relative 'vista_prescription_adapter'
require_relative 'oracle_health_prescription_adapter'
require_relative '../constants'
require_relative '../operation_outcome_detector'

module UnifiedHealthData
  module Adapters
    class PrescriptionsAdapter
      # Prescription status constants (STATUS_* / DISP_*) live in Constants::PrescriptionStatuses.
      include UnifiedHealthData::Constants::PrescriptionStatuses

      # Number of days after the most recent shipped date during which a prescription remains trackable.
      SHIPPED_TRACKING_WINDOW_DAYS = 15

      # Number of days a just-requested refill stays surfaced as in-flight ("Active: Submitted" /
      # "Active: Refill in Process") while VistA lags flipping the upstream disp_status.
      REFILL_IN_FLIGHT_WINDOW_DAYS = 3

      def initialize(current_user = nil)
        @current_user = current_user
        @vista_adapter = VistaPrescriptionAdapter.new
        @oracle_adapter = OracleHealthPrescriptionAdapter.new(current_user)
      end

      # @param body [Hash] The raw UHD response body
      # @param current_only [Boolean] When true, excludes discontinued/expired meds older than 180 days
      # @return [Hash] Hash with :prescriptions (Array) and :metadata (Hash) keys
      def parse(body, current_only: false)
        raise ArgumentError, 'UHD returned an empty response body' if body.nil?

        prescriptions = []

        # Parse VistA medications
        vista_medications = parse_vista_medications(body)
        prescriptions.concat(vista_medications) if vista_medications.present?

        # Parse Oracle Health medications
        oracle_medications = parse_oracle_medications(body)
        prescriptions.concat(oracle_medications) if oracle_medications.present?

        log_upstream_parse_counts(
          vista_count: vista_medications.size,
          oracle_count: oracle_medications.size,
          body:
        )

        # Exclude certain prescriptions based on business rules
        prescriptions.reject! { |prescription| should_exclude_prescription?(prescription) }

        # Apply current filtering if requested
        prescriptions = apply_current_filtering(prescriptions) if current_only

        # Apply shipped tracking logic (sets is_trackable to false if shipped beyond 15-day window)
        if Flipper.enabled?(:mhv_medications_management_improvements, @current_user)
          apply_shipped_tracking_logic(prescriptions)
          apply_awaiting_tracking_logic(prescriptions)
          apply_submission_date_bridge(prescriptions)
        end

        { prescriptions:, metadata: { has_failed_stations: any_source_failed?(body) } }
      end

      private

      def apply_current_filtering(prescriptions)
        filtered = prescriptions.reject { |prescription| prescription_not_current?(prescription) }

        Rails.logger.info(
          message: 'Applied current filtering to prescriptions',
          original_count: prescriptions.size,
          filtered_count: filtered.size,
          excluded_count: prescriptions.size - filtered.size
        )

        filtered
      end

      def prescription_not_current?(prescription)
        # Exclude discontinued/expired medications that are older than 180 days
        if %w[discontinued expired].include?(prescription.refill_status) &&
           prescription.expiration_date.present?
          begin
            expiration_date = Date.parse(prescription.expiration_date)
            return true if expiration_date < 180.days.ago
          rescue Date::Error, TypeError
            # If date parsing fails, don't exclude based on date
            # Only log last 4 digits of prescription ID for privacy
            rx_suffix = prescription.id.to_s.last(4)
            Rails.logger.warn("Invalid expiration date for rx ending in #{rx_suffix}: #{prescription.expiration_date}")
          end
        end

        false
      end

      def should_exclude_prescription?(prescription)
        # Mirror logic from Mobile::V0::PrescriptionsController#resource_data_modifications

        # Exclude Partial Fill (PF) and Pending Prescriptions (PD)
        display_pending_meds = Flipper.enabled?(:mhv_medications_display_pending_meds, @current_user)
        if display_pending_meds
          return true if prescription.prescription_source == 'PF'
        elsif %w[PF PD].include?(prescription.prescription_source)
          # TODO: remove this line when PF and PD are allowed on the app
          return true
        end

        # Exclude inpatient prescriptions
        # See https://build.fhir.org/valueset-medicationrequest-admin-location.html
        return true if prescription.category&.include?('inpatient')

        false
      end

      def parse_vista_medications(body)
        vista_data = body[SourceConstants::VISTA]
        return [] unless vista_data && vista_data['medicationList']

        medications = vista_data.dig('medicationList', 'medication')
        return [] unless medications.is_a?(Array)

        medications.map { |med| @vista_adapter.parse(med) }.compact
      end

      def parse_oracle_medications(body)
        oracle_data = body[SourceConstants::ORACLE_HEALTH]
        return [] unless oracle_data && oracle_data['entry']

        entries = oracle_data['entry']
        return [] unless entries.is_a?(Array)

        # Filter for MedicationRequest resources
        medication_requests = entries.select do |entry|
          entry.dig('resource', 'resourceType') == 'MedicationRequest'
        end

        medication_requests.map { |entry| @oracle_adapter.parse(entry['resource']) }.compact
      end

      # For prescriptions with disp_status 'Active: Shipped', checks the tracking shipped date
      # against a 15-day window. If shipped beyond 15 days, sets is_trackable to false.
      def apply_shipped_tracking_logic(prescriptions)
        prescriptions.each do |rx|
          next unless rx.disp_status == DISP_ACTIVE_SHIPPED

          most_recent_date = most_recent_shipped_date(rx)
          next unless most_recent_date

          rx.is_trackable = false unless most_recent_date >= SHIPPED_TRACKING_WINDOW_DAYS.days.ago
        end
      end

      def most_recent_shipped_date(rx)
        dates = rx.tracking.filter_map do |t|
          Time.zone.parse(t[:complete_date_time])
        rescue ArgumentError, TypeError
          nil
        end
        dates.max
      end

      # For prescriptions that have been recently dispensed (filled) but do not yet have
      # shipping/tracking information, reclassifies them as an in-progress refill. This covers
      # the gap between "Refill in progress" and "Refill shipped": once a fill completes the
      # prescription returns to an 'Active' disp_status with a dispensed date set, but no
      # tracking entry exists until the pharmacy ships it. Rather than surfacing a distinct
      # state, we treat the fill as "Refill in Process" so every surface renders the existing
      # in-progress treatment. The same 15-day window used for shipped tracking bounds how long
      # we keep a fill in this state. is_awaiting_tracking is retained as the detection signal.
      #
      # @param prescriptions [Array<UnifiedHealthData::Prescription>] parsed prescriptions, mutated in place
      # @return [void]
      def apply_awaiting_tracking_logic(prescriptions)
        prescriptions.each do |rx|
          if awaiting_tracking?(rx)
            rx.is_awaiting_tracking = true
            rx.disp_status = DISP_ACTIVE_REFILL_IN_PROCESS
            rx.refill_status = STATUS_REFILL_IN_PROCESS
            # There is no shipment yet, so there is nothing to track. Clear is_trackable so a
            # tracking affordance is not offered against an empty/incomplete tracking list.
            rx.is_trackable = false
          elsif pending_refill?(rx)
            reclassify_pending_refill(rx)
          else
            rx.is_awaiting_tracking = false
          end
        end
      end

      # Reclassifies a prescription whose refill was requested since the most recent fill while it
      # still reports a plain 'Active' disp_status because VistA can lag flipping the status to
      # submitted/refill-in-process. Surfaces the request so it stays visible on the refill status
      # page: a request without a projected refill date is still just "Request submitted", while one
      # with a refill date has progressed to "Fill in Process".
      #
      # @param rx [UnifiedHealthData::Prescription] the prescription to reclassify, mutated in place
      # @return [void]
      def reclassify_pending_refill(rx)
        rx.is_awaiting_tracking = false
        if projected_refill_scheduled?(rx)
          rx.disp_status = DISP_ACTIVE_REFILL_IN_PROCESS
          rx.refill_status = STATUS_REFILL_IN_PROCESS
        else
          rx.disp_status = DISP_ACTIVE_SUBMITTED
          rx.refill_status = STATUS_SUBMITTED
        end
        # No shipment exists yet, so there is nothing to track.
        rx.is_trackable = false
        # A refill has already been requested, so the prescription is not independently refillable
        # while it is surfaced as pending (matches the submission-date bridge behavior).
        rx.is_refillable = false
        log_pending_refill_reclassification(rx)
      end

      # A refill has progressed to "Fill in Process" only when a *projected* refill date exists
      # that is not older than the request itself. A refill_date that predates the submit date is
      # the previous fill, not a fill scheduled for the just-submitted request, so the request is
      # still only "Submitted". Without this guard a stale prior-fill date would mislabel a
      # freshly-submitted refill as already in process.
      def projected_refill_scheduled?(rx)
        refill_date = parse_date(rx.refill_date)
        return false if refill_date.nil?

        submit_date = parse_date(rx.refill_submit_date)
        return true if submit_date.nil?

        refill_date >= submit_date
      end

      # Determines whether a prescription is a recently dispensed *refill* fill that is still
      # awaiting shipping/tracking information. Qualifies only when the prescription is
      # 'Active', has no tracking entry yet, has at least one *refill* dispense (beyond the
      # initial fill), and its most recent dispensed date falls within the shipped-tracking
      # window.
      #
      # The refill-dispense requirement is essential: "Refill in Process" describes a refill
      # the veteran requested that has been filled but not yet shipped. A brand-new initial
      # fill must never be reclassified. The two EHR sources model dispenses differently, so
      # the check is source-aware (see #refill_dispense_present?): VistA dispenses are refills
      # only, but an Oracle Health initial fill is itself a MedicationDispense, so a bare
      # dispenses.blank? check would be a no-op for OH. is_refillable is intentionally NOT used
      # as the discriminator: a prescription with refills remaining can still report
      # isRefillable true while an already-requested refill is being filled/shipped.
      #
      # @param rx [UnifiedHealthData::Prescription] the prescription to evaluate
      # @return [Boolean] true when the fill is awaiting tracking, false otherwise
      def awaiting_tracking?(rx)
        return false unless rx.disp_status == DISP_ACTIVE
        return false if recent_tracking?(rx)
        return false unless refill_dispense_present?(rx)

        dispensed_date = most_recent_dispensed_date(rx)
        return false unless dispensed_date

        # sorted_dispensed_date is date-only, so compare at date granularity to keep
        # the 15-day boundary inclusive regardless of the current time of day.
        dispensed_date.to_date >= SHIPPED_TRACKING_WINDOW_DAYS.days.ago.to_date
      end

      # Determines whether a refill has been requested since the most recent fill while the
      # prescription still reports a plain 'Active' disp_status with no tracking yet. VistA can
      # lag flipping the status to 'Active: Submitted' / 'Active: Refill in Process' after a
      # refill request, which would otherwise leave the request invisible on the refill status
      # page. Bounded by the refill in-flight window, and requires the request to be newer than the
      # most recent dispense so already-completed fill cycles are not re-captured (a dispense
      # newer than the submit date means the request has already been filled).
      #
      # @param rx [UnifiedHealthData::Prescription] the prescription to evaluate
      # @return [Boolean] true when a not-yet-filled refill request is pending
      def pending_refill?(rx)
        return false unless vista_source?(rx)
        return false unless rx.disp_status == DISP_ACTIVE

        submit_date = parse_date(rx.refill_submit_date)
        return false unless submit_date
        return false unless submit_date >= REFILL_IN_FLIGHT_WINDOW_DAYS.days.ago.to_date

        # Date-bounded rather than presence-only: VistA tracking accumulates permanently across fill
        # cycles, so a stale complete_date_time from a prior shipment must not suppress a genuinely
        # new refill request. Only a shipment on/after the submit date counts as already filled.
        return false if shipped_since?(rx, submit_date)

        dispensed_date = most_recent_dispensed_date(rx)&.to_date
        # Use >= (not >) because refill_submit_date and dispensed_date are compared at day
        # granularity: a refill requested on the same calendar day as the most recent dispense is
        # a genuine new request and must still surface, otherwise same-day re-requests are dropped.
        dispensed_date.nil? || submit_date >= dispensed_date
      end

      # Whether the prescription carries a dispense that represents a *refill* (a fill beyond
      # the original/initial fill). The two EHR sources model dispenses differently:
      #
      #   - VistA: rx.dispenses is built from rxRFRecords (refill records only); the initial
      #     fill is a top-level dispensedDate and is never an rfRecord. Any dispense present
      #     therefore already represents a refill.
      #   - Oracle Health: rx.dispenses is built from every contained MedicationDispense, and
      #     the initial fill is itself a completed MedicationDispense. A refill exists only
      #     when more than one completed dispense is present — mirroring the refills-used math
      #     `completed_dispenses - 1` in OracleHealthRefillHelper#extract_refill_remaining.
      #
      # @param rx [UnifiedHealthData::Prescription] the prescription to evaluate
      # @return [Boolean] true when a refill dispense is present
      def refill_dispense_present?(rx)
        if rx.source_ehr == UnifiedHealthData::Prescription::SOURCE_EHR_ORACLE_HEALTH
          completed_dispenses(rx) > 1
        else
          rx.dispenses.present?
        end
      end

      # Counts Oracle Health dispenses with a 'completed' status. Voided dispenses
      # (status 'entered-in-error') and in-progress dispenses do not count as evidence
      # that a fill was actually handed over.
      #
      # @param rx [UnifiedHealthData::Prescription] the prescription to evaluate
      # @return [Integer] number of completed dispenses
      def completed_dispenses(rx)
        rx.dispenses.to_a.count do |d|
          d.is_a?(Hash) && (d[:status] || d['status']) == 'completed'
        end
      end

      # If any tracking entry has a completion date, the fill has shipped and is
      # therefore not awaiting tracking. Checks every entry (not just the first)
      # because tracking can contain multiple entries and any of them may carry the
      # completion date, while others can have a blank complete_date_time.
      #
      # @param rx [UnifiedHealthData::Prescription] the prescription to evaluate
      # @return [Boolean] true when a tracking entry with a completion date exists
      def recent_tracking?(rx)
        return false if rx.tracking.blank?

        rx.tracking.any? do |t|
          t.is_a?(Hash) && t[:complete_date_time].present?
        end
      end

      # The pending-refill heuristic exists solely to compensate for VistA lagging when it flips
      # a prescription's disp_status after a refill request.
      #
      # @param rx [UnifiedHealthData::Prescription] the prescription to evaluate
      # @return [Boolean] true when the prescription originates from VistA
      def vista_source?(rx)
        rx.source_ehr == UnifiedHealthData::Prescription::SOURCE_EHR_VISTA
      end

      # Emits a structured log when a prescription is reclassified via the pending_refill? path so
      # unexpected status changes can be traced and correlated with VistA lag timing. Only the last
      # 4 digits of the prescription id are logged to avoid exposing PII.
      #
      # @param rx [UnifiedHealthData::Prescription] the reclassified prescription
      # @return [void]
      def log_pending_refill_reclassification(rx)
        Rails.logger.info(
          message: 'UHD prescription reclassified via pending_refill',
          rx_id_suffix: rx.id.to_s.last(4),
          disp_status: rx.disp_status,
          refill_status: rx.refill_status,
          refill_submit_date: rx.refill_submit_date,
          most_recent_dispensed_date: rx.sorted_dispensed_date.presence || rx.dispensed_date
        )
      end

      def most_recent_dispensed_date(rx)
        raw = rx.sorted_dispensed_date.presence || rx.dispensed_date.presence
        return nil if raw.blank?

        Time.zone.parse(raw.to_s)
      rescue ArgumentError, TypeError
        nil
      end

      # Parses a date-only string into a Date, returning nil on blank or unparseable input.
      def parse_date(raw)
        return nil if raw.blank?

        # Time.zone.parse returns nil (rather than raising) for non-blank but unparseable input,
        # so guard the .to_date with safe navigation to avoid an unrescued NoMethodError.
        Time.zone.parse(raw.to_s)&.to_date
      rescue ArgumentError, TypeError
        nil
      end

      # Keeps a prescription showing "Active: Submitted" after a refill request while upstream
      # catches up, using persisted dates instead of the transient Redis badge. A submission newer
      # than the last fill (or a submission with no fill yet) means the refill is still pending.
      # Runs after the dispense-based tracking steps so those (shipped/awaiting) take precedence:
      # only prescriptions still showing plain 'Active' are bridged here. Gated to VistA only:
      # Oracle Health also populates refill_submit_date (from order Task executionPeriod), so an
      # ungated bridge would fire on OH prescriptions that OH already surfaces correctly.
      def apply_submission_date_bridge(prescriptions)
        prescriptions.each do |rx|
          next unless vista_source?(rx)
          next unless rx.disp_status == DISP_ACTIVE
          next unless refill_still_pending?(rx)

          rx.disp_status = DISP_ACTIVE_SUBMITTED
          rx.refill_status = STATUS_SUBMITTED
          rx.is_refillable = false
          # No shipment exists yet for a still-pending refill, so clear the upstream-sourced
          # is_trackable flag to avoid offering a tracking affordance against an empty list.
          rx.is_trackable = false
        end
      end

      def refill_still_pending?(rx)
        submit = parse_bridge_time(rx.refill_submit_date)
        return false if submit.nil?

        # Bound the bridge to the refill in-flight window. Without an upper bound a request
        # that never receives a dispense upstream would hold the prescription at "Active: Submitted"
        # with is_refillable=false indefinitely, re-creating the stuck-Submitted trap. After the
        # window elapses we stop bridging so the prescription falls back to its upstream status.
        return false if submit < REFILL_IN_FLIGHT_WINDOW_DAYS.days.ago

        # A fill that shipped on/after the submit date means this refill has been filled, so it is
        # no longer pending regardless of the projected refill_date. Compare the shipment completion
        # date against the submit date (rather than reusing the date-agnostic recent_tracking?) so
        # tracking left over from a *previous* fill cycle does not suppress a genuinely new request.
        return false if shipped_since?(rx, submit)

        # An actual dispense on/after the submit date means the request has already been filled.
        # refill_date below is VistA's *projected* next-available date, which is cleared/moved once a
        # fill lands; relying on it alone would re-stamp an already-dispensed refill back to
        # "Active: Submitted". Guard on the real dispensed date before consulting refill_date. Note
        # the boundary is intentionally the inverse of pending_refill?: there a same-day dispense
        # keeps a re-request pending (submit_date >= dispensed_date), whereas here a same-day
        # dispense counts as filled (dispensed >= submit) so a completed fill is never re-bridged.
        dispensed = most_recent_dispensed_date(rx)
        return false if dispensed && dispensed.to_date >= submit.to_date

        fill = parse_bridge_time(rx.refill_date)
        return true if fill.nil? # submitted, not yet filled

        submit > fill
      end

      def parse_bridge_time(value)
        return nil if value.blank?

        Time.zone.parse(value.to_s)
      rescue ArgumentError, TypeError
        nil
      end

      # Whether any tracking entry reports a shipment completed on/after the submit date. Unlike the
      # date-agnostic recent_tracking?, this compares each completion date to the submit date so a
      # shipment from a prior fill cycle does not count as evidence that the just-submitted refill
      # has already shipped.
      def shipped_since?(rx, submit)
        return false if rx.tracking.blank?

        rx.tracking.any? do |t|
          next false unless t.is_a?(Hash)

          completed = parse_bridge_time(t[:complete_date_time])
          completed && completed.to_date >= submit.to_date
        end
      end

      # Checks whether either data source reported a failure in the UHD response.
      # VistA: failedStationList is a non-empty string (comma-separated station numbers).
      # Oracle Health: entry array contains an OperationOutcome resource with error-severity issues.
      def any_source_failed?(body)
        vista_failed?(body) || oracle_health_failed?(body)
      end

      def vista_failed?(body)
        body.dig(SourceConstants::VISTA, 'failedStationList').present?
      end

      # Defense-in-depth: today the Client raises UpstreamPartialFailure for
      # error/fatal OperationOutcomes before the adapter runs, so this branch
      # is not reachable. We keep it aligned with OperationOutcomeDetector's
      # ERROR_SEVERITIES so the flag stays correct if that upstream flow changes.
      def oracle_health_failed?(body)
        oracle_data = body[SourceConstants::ORACLE_HEALTH]
        return false if oracle_data.blank?

        entries = oracle_data['entry']
        return false unless entries.is_a?(Array) && entries.present?

        entries.any? do |e|
          next false unless e.dig('resource', 'resourceType') == 'OperationOutcome'

          issues = e.dig('resource', 'issue')
          issues.is_a?(Array) && issues.any? do |i|
            OperationOutcomeDetector::ERROR_SEVERITIES.include?(i['severity'])
          end
        end
      end

      # Logs the raw counts from each data source after initial parsing.
      # This is the earliest point where we know what the upstream returned
      def log_upstream_parse_counts(vista_count:, oracle_count:, body:)
        vista_data = body[SourceConstants::VISTA]
        oracle_data = body[SourceConstants::ORACLE_HEALTH]

        Rails.logger.info(
          message: 'UHD prescriptions upstream parse counts',
          vista_raw_medications_parsed: vista_count,
          oracle_raw_medications_parsed: oracle_count,
          vista_medication_list_is_array: vista_data&.dig('medicationList', 'medication').is_a?(Array),
          oracle_entry_is_array: oracle_data&.dig('entry').is_a?(Array),
          vista_failed_station_list: vista_data&.dig('failedStationList').presence,
          service: 'unified_health_data'
        )
      end
    end
  end
end
