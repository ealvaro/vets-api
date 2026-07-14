# frozen_string_literal: true

require_relative 'gateways/benefits_intake_gateway'
require_relative 'gateways/decision_reviews_gateway'
require_relative 'gateways/hca1010_ez_gateway'
require_relative 'gateways/ivc_champva_gateway'
require_relative 'formatters/benefits_intake_formatter'
require_relative 'formatters/decision_reviews_formatter'
require_relative 'formatters/hca1010_ez_formatter'
require_relative 'formatters/ivc_champva_formatter'

module Forms
  module SubmissionStatuses
    class Report
      STATSD_KEY_PREFIX = 'api.forms.submission_statuses.gateway'
      STATUS_STATSD_KEY = "#{STATSD_KEY_PREFIX}.status".freeze

      # Submission statuses used for the `STATUS_STATSD_KEY` metric tags.
      KNOWN_STATUSES = %w[
        pending submitting submitted uploaded received processing success vbms error expired
        in_progress claimReceived complete
      ].freeze
      UNKNOWN_STATUS_TAG = 'other'
      BLANK_STATUS_TAG = 'none'

      FORMATTERS = {
        'lighthouse_benefits_intake' => Formatters::BenefitsIntakeFormatter.new,
        'decision_reviews' => Formatters::DecisionReviewsFormatter.new,
        'ivc_champva' => Formatters::IvcChampvaFormatter.new,
        'hca1010_ez' => Formatters::Hca1010EzFormatter.new
      }.freeze

      def initialize(user_account:, allowed_forms:, gateway_options: {})
        @gateways = build_enabled_gateways(user_account:, allowed_forms:, gateway_options:)
      end

      def run
        data
        format_data
      rescue => e
        Rails.logger.error(
          'Report execution failed in Forms::SubmissionStatuses::Report',
          error: e.message,
          service: @current_service,
          error_source: @current_operation,
          backtrace: e.backtrace[0..5]
        )
        raise
      end

      def data
        @datasets = @gateways.map do |gateway_config|
          @current_service = gateway_config[:service]
          @current_operation = 'data_retrieval_from_gateway'

          response = measure_gateway(@current_service) do
            gateway_config[:gateway].data
          end

          log_and_track_gateway_result(response)

          {
            service: @current_service,
            data: response
          }
        end
      end

      def format_data
        results = @datasets.flat_map do |dataset_config|
          service = dataset_config[:service]
          @current_service = service
          @current_operation = 'data_formatting'

          formatter = FORMATTERS[service]
          raise "Missing formatter for service: #{service}" unless formatter

          recent_results = formatter.format_data(dataset_config[:data]).select do |result|
            submission_recent?(result)
          end

          track_status_distribution(service, recent_results)
          recent_results
        end

        OpenStruct.new(
          submission_statuses: results,
          errors: @datasets.flat_map do |dataset|
            dataset[:data].errors
          end.compact
        )
      end

      private

      def build_enabled_gateways(user_account:, allowed_forms:, gateway_options:)
        gateways = []
        append_benefits_intake_gateway(gateways:, user_account:, allowed_forms:, gateway_options:)
        append_decision_reviews_gateway(gateways:, user_account:, allowed_forms:, gateway_options:)
        append_ivc_champva_gateway(gateways:, user_account:, gateway_options:)
        append_hca1010_ez_gateway(gateways:, user_account:, gateway_options:)
        gateways
      end

      def append_benefits_intake_gateway(gateways:, user_account:, allowed_forms:, gateway_options:)
        return unless gateway_options.fetch(:benefits_intake_enabled, true)

        gateways << {
          service: 'lighthouse_benefits_intake',
          gateway: Gateways::BenefitsIntakeGateway.new(user_account:, allowed_forms:)
        }
      end

      def append_decision_reviews_gateway(gateways:, user_account:, allowed_forms:, gateway_options:)
        return unless gateway_options.fetch(:decision_reviews_enabled, false)

        gateways << {
          service: 'decision_reviews',
          gateway: Gateways::DecisionReviewsGateway.new(user_account:, allowed_forms:)
        }
      end

      def append_ivc_champva_gateway(gateways:, user_account:, gateway_options:)
        return unless gateway_options.fetch(:ivc_champva_enabled, false)

        gateways << {
          service: 'ivc_champva',
          gateway: Gateways::IvcChampvaGateway.new(
            user_account:,
            user_email: gateway_options[:user_email]
          )
        }
      end

      def append_hca1010_ez_gateway(gateways:, user_account:, gateway_options:)
        return unless gateway_options.fetch(:hca_status_card_enabled, false)

        gateways << {
          service: 'hca1010_ez',
          gateway: Gateways::Hca1010EzGateway.new(user_account:)
        }
      end

      def submission_recent?(submission)
        return submission.created_at >= 60.days.ago unless submission.updated_at

        submission.updated_at >= 60.days.ago
      end

      def log_and_track_gateway_result(response)
        if response.errors.present?
          StatsD.increment(STATSD_KEY_PREFIX, tags: ["service:#{@current_service}", 'result:error'])
          Rails.logger.error(
            'Gateway errors encountered when retrieving data in Forms::SubmissionStatuses::Report',
            service: @current_service,
            errors: response.errors
          )
        else
          StatsD.increment(STATSD_KEY_PREFIX, tags: ["service:#{@current_service}", 'result:success'])
        end
      end

      # Emits a per-status, per-gateway counter feeding the submission-status
      # distribution panels in Datadog.
      def track_status_distribution(service, results)
        status_counts = Hash.new(0)
        unrecognized_counts = Hash.new(0)

        results.each do |result|
          raw_status = result.status.to_s
          normalized = normalize_status_tag(raw_status)
          status_counts[normalized] += 1
          unrecognized_counts[raw_status] += 1 if normalized == UNKNOWN_STATUS_TAG
        end

        status_counts.each do |status, count|
          StatsD.increment(STATUS_STATSD_KEY, count, tags: ["service:#{service}", "status:#{status}"])
        end

        log_unrecognized_statuses(service, unrecognized_counts)
      end

      def normalize_status_tag(status)
        status = status.to_s
        return BLANK_STATUS_TAG if status.blank?

        KNOWN_STATUSES.include?(status) ? status : UNKNOWN_STATUS_TAG
      end

      # Logs the raw status string(s) bucketed to `other` (PII-safe) so a
      # `status:other` spike in Datadog can be traced to the unmapped value.
      def log_unrecognized_statuses(service, unrecognized_counts)
        return if unrecognized_counts.empty?

        Rails.logger.warn(
          'Unrecognized submission status(es) bucketed to "other" in Forms::SubmissionStatuses::Report',
          service:,
          unrecognized_statuses: unrecognized_counts
        )
      end

      def measure_gateway(service)
        start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        result = yield
        result
      ensure
        duration = (Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time) * 1000
        StatsD.measure("#{STATSD_KEY_PREFIX}.latency", duration, tags: ["service:#{service}"])
      end
    end
  end
end
