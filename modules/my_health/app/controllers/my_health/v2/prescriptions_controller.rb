# frozen_string_literal: true

require 'unified_health_data/constants'
require 'unified_health_data/prescription_service'
require 'unified_health_data/serializers/prescriptions_refills_serializer'
require 'mhv/prescriptions/oh_transition_refill_filter'
require 'mhv/prescriptions/refill_request_tracker'
require 'securerandom'
require 'unique_user_events'
require 'vets/collection'

module MyHealth
  module V2
    class PrescriptionsController < ApplicationController
      include Filterable
      include MyHealth::PrescriptionHelperV2::Filtering
      include MyHealth::PrescriptionHelperV2::Sorting
      include MyHealth::RxGroupingHelperV2
      include JsonApiPaginationLinks

      service_tag 'mhv-medications'

      ACTIVE_STATUSES_V1 = [
        'Active', 'Active: Refill in Process', 'Active: Non-VA',
        'Active: Parked', 'Active: Submitted'
      ].freeze

      IN_PROGRESS_STATUSES_V1 = ['Active: Refill in Process', 'Active: Submitted'].freeze

      NON_ACTIVE_STATUSES_V1 = ['Expired', 'Discontinued', 'Active: On hold'].freeze

      UNKNOWN_STATUS_V1 = 'Unknown'

      # Submits prescription refill orders to the upstream service.
      # Orders blocked by OH transition rules are partitioned out before submission.
      # Renders a merged result of successful, failed, and blocked refills.
      def refill
        parsed_orders = orders
        track_refills_requested_by_station(parsed_orders)
        allowed_orders, blocked_failures = oh_transition_filter.partition_orders(parsed_orders)
        claimed_orders, duplicate_failures = refill_request_tracker.claim_orders(allowed_orders)

        begin
          # Only call upstream service if there are non-blocked and non-duplicate orders
          api_result = refill_api_result(claimed_orders)
          release_failed_claims_for(api_result, claimed_orders)
        rescue Common::Exceptions::BackendServiceException
          # Upstream failed before returning a structured refill result, so release claims to allow retry.
          release_failed_claims(claimed_orders)
          raise
        end

        increment_uhd_refill(api_result[:success].size) if api_result[:success].present?
        render_refill_response(api_result, duplicate_failures, blocked_failures)
        log_refill_requested_event(parsed_orders)
      end

      # This index action supports various parameters described below, all are optional
      # @param refill_status - one refill status to filter on
      # @param page - the paginated page to fetch
      # @param per_page - the number of items to fetch per page
      # @param sort - the attribute to sort on, negated for descending, use sort[]= for multiple argument query params
      #        (ie: ?sort[]=refill_status&sort[]=-prescription_id)
      def index
        result = service.get_prescriptions(current_only: false)
        prescriptions = apply_recent_submission_overrides(result[:prescriptions].compact)
        source_metadata = result[:metadata]

        recently_requested = get_recently_requested_prescriptions(prescriptions)
        all_medications_count = count_grouped_prescriptions(prescriptions)
        prescriptions = resource_data_modifications(prescriptions).compact

        filter_metadata = build_filter_metadata(prescriptions, all_medications_count)
        prescriptions, sort_metadata = apply_filters_and_sorting(prescriptions)

        records, options = build_response_data(prescriptions, filter_metadata, recently_requested, sort_metadata)
        options[:meta] = options[:meta].merge(source_metadata)

        log_prescriptions_access
        render json: MyHealth::V2::PrescriptionDetailsSerializer.new(records, options)
      end

      # Retrieves a single prescription by ID and station number.
      #
      # @param id [String] the prescription ID (path param)
      # @param station_number [String] the station number (query param, required)
      def show
        raise Common::Exceptions::ParameterMissing, 'station_number' if params[:station_number].blank?

        prescriptions = apply_recent_submission_overrides(
          service.get_prescriptions(current_only: false)[:prescriptions].compact
        )
        # Filter out discontinued non-VA meds
        prescriptions = filter_discontinued_non_va_meds(prescriptions)
        prescription = prescriptions.find do |p|
          p.prescription_id.to_s == params[:id].to_s &&
            p.station_number.to_s == params[:station_number].to_s
        end

        raise Common::Exceptions::RecordNotFound, params[:id] unless prescription

        render json: MyHealth::V2::PrescriptionDetailsSerializer.new(prescription)
      end

      # Returns prescriptions that are eligible for refill or renewal.
      # Includes recently requested prescriptions in response metadata.
      def list_refillable_prescriptions
        prescriptions = apply_recent_submission_overrides(
          service.get_prescriptions(current_only: false)[:prescriptions].compact
        )
        # Filter out discontinued non-VA meds
        prescriptions = filter_discontinued_non_va_meds(prescriptions)
        recently_requested = get_recently_requested_prescriptions(prescriptions)
        refillable_prescriptions = filter_data_by_refill_and_renew(prescriptions)

        options = { meta: { recently_requested: } }
        render json: MyHealth::V2::PrescriptionDetailsSerializer.new(refillable_prescriptions, options)
      end

      # Returns only the count of prescriptions that are refillable.
      # This is a lightweight endpoint for the My VA Prescriptions card.
      def refillable_count
        prescriptions = apply_recent_submission_overrides(
          service.get_prescriptions(current_only: false)[:prescriptions].compact
        )
        prescriptions = filter_discontinued_non_va_meds(prescriptions)
        count = prescriptions.count(&:is_refillable)

        render json: {
          data: {
            refillable_count: count,
            timestamp: Time.current.iso8601
          }
        }
      end

      private

      def service
        @service ||= UnifiedHealthData::PrescriptionService.new(@current_user)
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

      def refill_request_tracker
        @refill_request_tracker ||= MHV::Prescriptions::RefillRequestTracker.new(@current_user)
      end

      def apply_filters_and_sorting(prescriptions)
        prescriptions = apply_filters_to_list(prescriptions) if params[:filter].present?
        prescriptions, sort_metadata = apply_sorting_to_list(prescriptions, params[:sort])
        # Only move PD prescriptions to top when using default sort
        prescriptions = sort_prescriptions_with_pd_at_top(prescriptions) if params[:sort].blank?
        [prescriptions, sort_metadata]
      end

      def build_response_data(prescriptions, filter_metadata, recently_requested, sort_metadata = {})
        is_using_pagination = params[:page].present? || params[:per_page].present?

        base_meta = filter_metadata.merge(recently_requested:)
        # sort_metadata is the entire metadata hash from the resource, access the :sort key
        base_meta[:sort] = sort_metadata[:sort] if sort_metadata.is_a?(Hash) && sort_metadata[:sort].present?

        if is_using_pagination
          build_paginated_response(prescriptions, base_meta)
        else
          [Array(prescriptions), { meta: base_meta }]
        end
      end

      def build_paginated_response(prescriptions, base_meta)
        collection = Vets::Collection.new(prescriptions)
        page, per_page = normalized_pagination_values
        paginated = collection.paginate(page:, per_page:)

        pagination_meta = paginated.metadata[:pagination]
        options = {
          meta: base_meta.merge(pagination: pagination_meta),
          links: build_pagination_links(
            current_page: pagination_meta[:current_page],
            per_page: pagination_meta[:per_page],
            total_pages: pagination_meta[:total_pages]
          )
        }
        [paginated.data, options]
      rescue Common::Exceptions::InvalidPaginationParams
        Rails.logger.warn(
          'Prescriptions pagination out of bounds',
          page:, per_page:, total: collection.size
        )
        build_empty_paginated_response(collection, base_meta, page, per_page)
      end

      def build_empty_paginated_response(collection, base_meta, page, per_page)
        pagination = Vets::Collections::Pagination.new(
          page:,
          per_page:,
          total_entries: collection.size,
          data: nil
        )

        # Extract total_pages for link generation; full metadata is merged into options[:meta] below
        total_pages = pagination.metadata.dig(:pagination, :total_pages)

        options = {
          meta: base_meta.merge(pagination: pagination.metadata[:pagination]),
          links: build_pagination_links(current_page: page, per_page:, total_pages:)
        }

        [[], options]
      end

      def normalized_pagination_values
        page = pagination_params[:page].to_i
        per_page = pagination_params[:per_page].to_i

        page = 1 unless page.positive?
        per_page = Vets::Collection::DEFAULT_PER_PAGE unless per_page.positive?
        per_page = [per_page, Vets::Collection::DEFAULT_MAX_PER_PAGE].min

        [page, per_page]
      end

      def log_prescriptions_access
        UniqueUserEvents.log_event(
          user: @current_user,
          event_name: UniqueUserEvents::EventRegistry::PRESCRIPTIONS_ACCESSED
        )
      end

      def get_recently_requested_prescriptions(prescriptions)
        prescriptions.select do |item|
          item.respond_to?(:disp_status) && in_progress_statuses.include?(item.disp_status)
        end
      end

      def in_progress_statuses
        IN_PROGRESS_STATUSES_V1
      end

      def apply_filters_to_list(prescriptions)
        filter_params = params.require(:filter).permit(disp_status: [:eq], is_trackable: [:eq], is_renewable: [:eq])
        disp_status = filter_params[:disp_status]
        is_trackable = filter_params[:is_trackable]
        is_renewable = filter_params[:is_renewable]

        prescriptions = apply_disp_status_filter(prescriptions, disp_status) if disp_status.present?
        prescriptions = apply_trackable_filter(prescriptions, is_trackable) if is_trackable.present?
        prescriptions = apply_renewable_filter(prescriptions, is_renewable) if is_renewable.present?

        prescriptions
      end

      def apply_disp_status_filter(prescriptions, disp_status)
        filters = disp_status[:eq].split(',').map(&:strip).map(&:downcase)
        prescriptions.select do |item|
          item.respond_to?(:disp_status) && item.disp_status &&
            filters.include?(item.disp_status.downcase)
        end
      end

      def apply_trackable_filter(prescriptions, is_trackable)
        filter_value = is_trackable[:eq] == 'true'
        if filter_value
          prescriptions.select { |item| shipped?(item) }
        else
          prescriptions.reject { |item| shipped?(item) }
        end
      end

      def apply_renewable_filter(prescriptions, is_renewable)
        filter_value = is_renewable[:eq] == 'true'
        if filter_value
          prescriptions.select { |item| item.is_renewable == true }
        else
          prescriptions.reject { |item| item.is_renewable == true }
        end
      end

      def shipped?(item)
        item.respond_to?(:disp_status) && item.respond_to?(:is_trackable) &&
          item.disp_status == 'Active' && item.is_trackable == true
      end

      def apply_sorting_to_list(prescriptions, sort_param)
        # Create a mock resource object for the helper methods
        resource = Struct.new(:records, :metadata).new(prescriptions, {})

        # Use the helper's apply_sorting method which sets the metadata
        sorted_resource = apply_sorting(resource, sort_param)

        [sorted_resource.records, sorted_resource.metadata]
      end

      def resource_data_modifications(prescriptions)
        display_pending_meds = Flipper.enabled?(:mhv_medications_display_pending_meds, @current_user)

        prescriptions = if params[:filter].blank? && display_pending_meds
                          prescriptions.reject do |item|
                            item.respond_to?(:prescription_source) && item.prescription_source == 'PF'
                          end
                        else
                          remove_pf_pd(prescriptions)
                        end

        # Filter out discontinued non-VA meds
        prescriptions = filter_discontinued_non_va_meds(prescriptions)

        group_prescriptions(prescriptions)
      end

      def build_filter_metadata(list, all_medications_count)
        {
          filter_count: {
            all_medications: all_medications_count,
            active: count_active_medications(list),
            in_progress: count_in_progress_medications(list),
            shipped: count_shipped_medications(list),
            renewable: count_renewable_medications(list),
            inactive: count_non_active_medications(list),
            transferred: count_transferred_medications(list),
            status_not_available: count_unknown_status_medications(list)
          }
        }
      end

      def count_active_medications(list)
        active_statuses = ACTIVE_STATUSES_V1
        list.count { |rx| rx.respond_to?(:disp_status) && active_statuses.include?(rx.disp_status) }
      end

      def count_in_progress_medications(list)
        list.count { |item| item.respond_to?(:disp_status) && in_progress_statuses.include?(item.disp_status) }
      end

      def count_non_active_medications(list)
        non_active_statuses = NON_ACTIVE_STATUSES_V1
        list.count { |rx| rx.respond_to?(:disp_status) && non_active_statuses.include?(rx.disp_status) }
      end

      def count_shipped_medications(list)
        # Shipped: disp_status is Active AND is_trackable is true
        list.count { |rx| shipped?(rx) }
      end

      def count_renewable_medications(list)
        list.count { |rx| rx.is_renewable == true }
      end

      def count_transferred_medications(list)
        list.count { |rx| rx.respond_to?(:disp_status) && rx.disp_status == 'Transferred' }
      end

      def count_unknown_status_medications(list)
        unknown_status = UNKNOWN_STATUS_V1
        list.count { |rx| rx.respond_to?(:disp_status) && rx.disp_status == unknown_status }
      end

      def in_progress_display_status
        IN_PROGRESS_STATUSES_V1.last
      end

      def apply_recent_submission_overrides(prescriptions)
        refill_request_tracker.apply_submitted_state!(
          prescriptions,
          in_progress_status: in_progress_display_status
        )
        prescriptions
      end

      def refill_api_result(claimed_orders)
        return { success: [], failed: [] } if claimed_orders.blank?

        service.refill_prescription(claimed_orders)
      end

      def release_failed_claims_for(api_result, claimed_orders)
        return if retain_claims_after_service_response?(api_result, claimed_orders)

        release_failed_claims(api_result[:failed])
      end

      def release_failed_claims(failed_orders)
        refill_request_tracker.release_orders(failed_orders)
      end

      def render_refill_response(api_result, duplicate_failures, blocked_failures)
        merged_result = MHV::Prescriptions::OhTransitionRefillFilter.merge_results(api_result, duplicate_failures)
        merged_result = MHV::Prescriptions::OhTransitionRefillFilter.merge_results(merged_result, blocked_failures)
        response = UnifiedHealthData::Serializers::PrescriptionsRefillsSerializer.new(SecureRandom.uuid, merged_result)

        render json: response.serializable_hash
      end

      def log_refill_requested_event(parsed_orders)
        # Also logs OH-specific events if any facility IDs match tracked OH facilities.
        event_facility_ids = parsed_orders.map { |order| order['stationNumber'] }.compact.uniq
        UniqueUserEvents.log_event(
          user: @current_user,
          event_name: UniqueUserEvents::EventRegistry::PRESCRIPTIONS_REFILL_REQUESTED,
          event_facility_ids:
        )
      end

      # Keep claims when the entire request failed with generic service-unavailable errors.
      # In that scenario we cannot safely infer whether upstream accepted any orders.
      def retain_claims_after_service_response?(api_result, claimed_orders)
        successes = Array(api_result[:success])
        failures = Array(api_result[:failed])

        return false unless successes.empty?
        return false unless claimed_orders.present? && failures.length == claimed_orders.length

        failures.all? do |failure|
          failure[:error].to_s == MHV::Prescriptions::RefillRequestTracker::SERVICE_UNAVAILABLE_ERROR
        end
      end

      def remove_pf_pd(data)
        sources_to_remove_from_data = %w[PF PD]
        data.reject do |item|
          item.respond_to?(:prescription_source) && sources_to_remove_from_data.include?(item.prescription_source)
        end
      end

      def sort_prescriptions_with_pd_at_top(prescriptions)
        pd, others = prescriptions.partition do |med|
          med.respond_to?(:prescription_source) && med.prescription_source == 'PD'
        end
        pd + others
      end

      def orders
        @orders ||= begin
          parsed_orders = JSON.parse(request.body.read)

          # Validate that orders is an array
          unless parsed_orders.is_a?(Array)
            raise Common::Exceptions::InvalidFieldValue.new('orders',
                                                            'Must be an array')
          end

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
end
