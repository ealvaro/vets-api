# frozen_string_literal: true

require 'unified_health_data/constants'
require 'unified_health_data/prescription_service'
require 'unified_health_data/serializers/prescription_serializer'
require 'unified_health_data/serializers/prescriptions_refills_serializer'
require 'mhv/prescriptions/oh_transition_refill_filter'
require 'securerandom'
require 'unique_user_events'

module Mobile
  module V1
    class PrescriptionsController < Mobile::ApplicationController
      before_action { authorize :mhv_prescriptions, :access? }

      # Returns paginated, filtered prescriptions for the authenticated user.
      # Excludes Non-VA (NV) meds from the response data but reports their presence in meta.
      def index
        all_prescriptions = fetch_prescriptions
        pruned = filtered_prescriptions(all_prescriptions)
        paged, page_meta = paginate_prescriptions(pruned)
        meta = build_meta(full_list: pruned, page_meta:, originals: all_prescriptions)

        # Log unique user event for prescriptions accessed
        UniqueUserEvents.log_event(
          user: @current_user,
          event_name: UniqueUserEvents::EventRegistry::PRESCRIPTIONS_ACCESSED
        )

        serialized = UnifiedHealthData::Serializers::PrescriptionSerializer.new(paged).serializable_hash
        render json: { **serialized, meta: }
      rescue Common::Exceptions::BackendServiceException
        raise Common::Exceptions::BackendServiceException, 'MOBL_502_upstream_error'
      end

      # Submits a batch refill request for the given prescription orders.
      # Orders targeting OH-transition-blocked facilities are partitioned out and reported as failures.
      def refill
        parsed_orders = orders
        track_refills_requested_by_station(parsed_orders)
        allowed_orders, blocked_failures = oh_transition_filter.partition_orders(parsed_orders)

        # Only call upstream service if there are non-blocked orders
        api_result = if allowed_orders.present?
                       unified_health_service.refill_prescription(allowed_orders)
                     else
                       { success: [], failed: [] }
                     end

        increment_uhd_refill(api_result[:success].size) if api_result[:success].present?

        merged_result = MHV::Prescriptions::OhTransitionRefillFilter.merge_results(api_result, blocked_failures)
        response = UnifiedHealthData::Serializers::PrescriptionsRefillsSerializer.new(SecureRandom.uuid, merged_result)
        raise Common::Exceptions::BackendServiceException, 'MOBL_502_upstream_error' unless response

        # Log unique user event for prescription refill requested (includes OH tracking for matching facilities)
        event_facility_ids = parsed_orders.map { |order| order['stationNumber'] }.compact.uniq
        UniqueUserEvents.log_event(
          user: @current_user,
          event_name: UniqueUserEvents::EventRegistry::PRESCRIPTIONS_REFILL_REQUESTED,
          event_facility_ids:
        )

        render json: response.serializable_hash
      end

      private

      def unified_health_service
        @unified_health_service ||= UnifiedHealthData::PrescriptionService.new(@current_user)
      end

      def log_upstream_type_error(action, error)
        monitor.track_request(
          :error,
          'TypeError from upstream identity resolution',
          'mobile.prescriptions.upstream_type_error',
          call_location: error.backtrace_locations&.first,
          action:,
          error_class: error.class.name,
          error_message: error.message
        )
      end

      def monitor
        @monitor ||= Logging::Monitor.new(
          'mobile-prescriptions',
          allowlist: %i[action error_class error_message]
        )
      end

      def increment_uhd_refill(count)
        StatsD.increment("#{UnifiedHealthData::Constants::STATSD_KEY_PREFIX}.refills.requested", count,
                         tags: ["source_app:#{request.env['SOURCE_APP']}"])
      end

      def track_refills_requested_by_station(orders)
        station_counts = orders.map { |o| o['stationNumber'] }.compact.tally
        station_counts.each do |station, count|
          StatsD.increment("#{UnifiedHealthData::Constants::STATSD_KEY_PREFIX}.refills.requested_by_station",
                           count, tags: ["station_number:#{station}", "source_app:#{request.env['SOURCE_APP']}"])
        end
      end

      def oh_transition_filter
        @oh_transition_filter ||= MHV::Prescriptions::OhTransitionRefillFilter.new(
          @current_user, source_app: request.env['SOURCE_APP']
        )
      end

      def fetch_prescriptions
        unified_health_service.get_prescriptions(current_only: true)[:prescriptions]
      rescue TypeError => e
        log_upstream_type_error('fetch_prescriptions', e)
        raise Common::Exceptions::BackendServiceException, 'MOBL_502_upstream_error'
      end

      def filtered_prescriptions(list)
        list.reject { |item| item.prescription_source == 'NV' }
      end

      def pagination_contract
        Mobile::V0::Contracts::Prescriptions.new.call(
          page_number: params.dig(:page, :number),
          page_size: params.dig(:page, :size),
          filter: nil,
          sort: params[:sort]
        )
      end

      def paginate_prescriptions(list)
        Mobile::PaginationHelper.paginate(list:, validated_params: pagination_contract)
      end

      def build_meta(full_list:, page_meta:, originals:)
        meta = page_meta[:meta]
        meta.merge!(status_meta(full_list))
        meta.merge!(has_non_va_meds: non_va_meds?(originals))
        meta
      end

      def status_meta(prescriptions)
        counts = prescriptions.each_with_object(Hash.new(0)) do |obj, hash|
          hash['isRefillable'] += 1 if obj.is_refillable

          if obj.is_trackable || %w[active submitted providerHold activeParked
                                    refillinprocess].include?(obj.refill_status)
            hash['active'] += 1
          else
            hash[obj.refill_status] += 1
          end
        end

        { prescription_status_count: { 'isRefillable' => 0, 'active' => 0 }.merge(counts) }
      end

      def non_va_meds?(prescriptions)
        prescriptions.any? { |rx| rx.prescription_source == 'NV' }
      end

      def orders
        parsed_orders = JSON.parse(request.body.read)

        # Validate that orders is an array
        raise Common::Exceptions::InvalidFieldValue.new('orders', 'Must be an array') unless parsed_orders.is_a?(Array)

        # Validate that orders array is not empty (treat empty array same as missing required parameter)
        raise Common::Exceptions::ParameterMissing, 'orders' if parsed_orders.empty?

        # Validate that each order has required fields
        parsed_orders.each_with_index do |order, index|
          unless order.is_a?(Hash) && order['stationNumber'] && order['id']
            raise Common::Exceptions::InvalidFieldValue.new(
              "orders[#{index}]",
              'Each order must contain stationNumber and id fields'
            )
          end
        end

        parsed_orders
      rescue JSON::ParserError
        raise Common::Exceptions::InvalidFieldValue.new('orders', 'Invalid JSON format')
      end
    end
  end
end
