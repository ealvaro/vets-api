# frozen_string_literal: true

require_relative 'base_service'
require_relative 'models/prescription'
require_relative 'adapters/prescriptions_adapter'

module UnifiedHealthData
  class PrescriptionService < UnifiedHealthData::BaseService
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
      if result[:prescriptions].size.zero?
        Rails.logger.info(
          message: 'UHD prescriptions not found',
          total_prescriptions: result[:prescriptions].size,
          current_filtering_applied: current_only,
          icn: @user&.icn,
          has_failed_stations: result[:metadata][:has_failed_stations],
          service: 'unified_health_data'
        )
      else
        Rails.logger.info(
          message: 'UHD prescriptions retrieved',
          total_prescriptions: result[:prescriptions].size,
          current_filtering_applied: current_only,
          icn: @user&.icn,
          has_failed_stations: result[:metadata][:has_failed_stations],
          service: 'unified_health_data'
        )
      end
    end
  end
end
