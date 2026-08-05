# frozen_string_literal: true

require_relative 'base_service'
require_relative 'constants'
require_relative 'models/prescription'
require_relative 'adapters/prescriptions_adapter'

module UnifiedHealthData
  class PrescriptionService < UnifiedHealthData::BaseService
    # Display statuses that count as "in progress" for list-summary logging.
    # Downstream APIs return these VistA-style statuses (never the literal "In progress").
    # Keep in sync with MyHealth::V2::PrescriptionsController::IN_PROGRESS_STATUSES_V1.
    IN_PROGRESS_DISP_STATUSES = [
      'active: refill in process',
      'active: submitted'
    ].freeze

    # Retrieves prescriptions for the current user from unified health data sources
    #
    # @param current_only [Boolean] When true, applies filtering logic to exclude:
    #   - Discontinued/expired medications older than 180 days
    #   Defaults to false to return all prescriptions without filtering
    # @return [Hash] Hash with :prescriptions (Array<UnifiedHealthData::Prescription>) and
    #   :metadata (Hash including :has_failed_stations Boolean)
    def get_prescriptions(current_only: false)
      validate_icn!
      with_monitoring do
        start_date = default_start_date
        end_date = default_end_date
        response = uhd_client.get_prescriptions_by_date(patient_id: @user.icn, start_date:, end_date:)
        body = response.body

        adapter = UnifiedHealthData::Adapters::PrescriptionsAdapter.new(@user)
        result = adapter.parse(body, current_only:)
        log_prescriptions_result(result, current_only)

        result
      end
    end

    def refill_prescription(orders)
      validate_icn!
      normalized_orders = normalize_orders(orders)
      with_monitoring do
        response = uhd_client.refill_prescription_orders(build_refill_request_body(normalized_orders))
        result = parse_refill_response(response)
        validate_refill_response_count(normalized_orders, result)
        result
      end
    rescue Common::Exceptions::BackendServiceException => e
      raise e if e.original_status && e.original_status >= 500
    rescue => e
      Rails.logger.error("Error submitting prescription refill: #{e.message}")
      build_error_response(normalized_orders)
    end

    private

    def build_refill_request_body(orders)
      {
        patientId: @user.icn,
        orders: orders.map do |order|
          {
            orderId: order[:id].to_s,
            stationNumber: order[:stationNumber].to_s
          }
        end
      }
    end

    def build_error_response(orders)
      {
        success: [],
        failed: orders.map do |order|
          { id: order[:id], error: 'Service unavailable', station_number: order[:stationNumber] }
        end
      }
    end

    def normalize_orders(orders)
      return [] if orders.blank?

      orders.map do |order|
        next order unless order.respond_to?(:with_indifferent_access)

        order.with_indifferent_access
      end
    end

    def parse_refill_response(response)
      body = response.body
      refill_items = body.is_a?(Array) ? body : []
      successes = extract_successful_refills(refill_items)
      failures = extract_failed_refills(refill_items)

      {
        success: successes || [],
        failed: failures || []
      }
    end

    def validate_refill_response_count(normalized_orders, result)
      orders_sent = normalized_orders.size
      orders_received = result[:success].size + result[:failed].size

      return if orders_sent == orders_received

      error_message = "Refill response count mismatch: sent #{orders_sent} orders, " \
                      "received #{orders_received} responses"
      Rails.logger.error(error_message)
      raise Common::Exceptions::PrescriptionRefillResponseMismatch.new(orders_sent, orders_received)
    end

    def extract_successful_refills(refill_items)
      successful_refills = refill_items.select { |item| item['success'] == true }
      successful_refills.map do |refill|
        order = refill['order'] || refill
        {
          id: order['orderId'],
          status: refill['message'] || 'submitted',
          station_number: order['stationNumber']
        }
      end
    end

    def extract_failed_refills(refill_items)
      failed_refills = refill_items.select { |item| item['success'] == false }
      failed_refills.map do |failure|
        order = failure['order'] || failure
        {
          id: order['orderId'],
          error: failure['message'] || 'Unable to process refill',
          station_number: order['stationNumber']
        }
      end
    end

    def log_prescriptions_result(result, current_only)
      prescriptions = Array(result[:prescriptions])
      summary = prescription_status_summary(prescriptions)
      Rails.logger.info(prescription_list_log_payload(result, current_only, summary))
      emit_prescription_list_statsd(summary)
    rescue => e
      Rails.logger.warn(
        'UHD prescriptions summary logging failed',
        error_class: e.class.name,
        error_message: e.message.to_s
      )
    end

    def prescription_status_summary(prescriptions)
      by_disp = status_histogram(prescriptions, :disp_status)
      by_refill = status_histogram(prescriptions, :refill_status)
      {
        total: prescriptions.size,
        by_disp_status: by_disp,
        by_refill_status: by_refill,
        suspended_refill_count: count_matching(by_refill, 'suspended'),
        suspended_disp_count: count_matching(by_disp, 'suspended'),
        status_not_available_count: count_matching(by_disp, 'status not available') +
          count_matching(by_disp, 'unknown'),
        in_progress_count: in_progress_total(by_disp),
        active_count: count_matching(by_disp, 'active'),
        blank_status_count: by_disp['blank'].to_i
      }
    end

    def prescription_list_log_payload(result, current_only, summary)
      {
        message: summary[:total].zero? ? 'UHD prescriptions not found' : 'UHD prescriptions retrieved',
        total_prescriptions: summary[:total],
        current_filtering_applied: current_only,
        # ICNs are PII — do not log them (use user_uuid for Datadog correlation).
        user_uuid: @user&.uuid,
        has_failed_stations: result.dig(:metadata, :has_failed_stations),
        service: 'unified_health_data',
        by_disp_status: summary[:by_disp_status],
        by_refill_status: summary[:by_refill_status],
        suspended_refill_count: summary[:suspended_refill_count],
        suspended_disp_count: summary[:suspended_disp_count],
        status_not_available_count: summary[:status_not_available_count],
        in_progress_count: summary[:in_progress_count],
        active_count: summary[:active_count],
        blank_status_count: summary[:blank_status_count]
      }
    end

    def status_histogram(collection, attribute)
      histogram = Array(collection).each_with_object(Hash.new(0)) do |item, counts|
        next unless item.respond_to?(attribute)

        raw = item.public_send(attribute)
        key = raw.present? ? raw.to_s.downcase : 'blank'
        counts[key] += 1
      end
      {}.merge(histogram)
    end

    def count_matching(histogram, status_key)
      histogram[status_key.to_s.downcase].to_i
    end

    def in_progress_total(by_disp)
      IN_PROGRESS_DISP_STATUSES.sum { |status| count_matching(by_disp, status) }
    end

    def emit_prescription_list_statsd(summary)
      prefix = "#{Constants::STATSD_KEY_PREFIX}.prescriptions.index"
      StatsD.gauge("#{prefix}.total", summary[:total])
      StatsD.gauge("#{prefix}.suspended_refill", summary[:suspended_refill_count])
      StatsD.gauge("#{prefix}.in_progress", summary[:in_progress_count])
      StatsD.gauge("#{prefix}.status_not_available", summary[:status_not_available_count])
      return unless summary[:suspended_refill_count].positive?

      StatsD.increment("#{prefix}.with_suspended_refill")
    end
  end
end
