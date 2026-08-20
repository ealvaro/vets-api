# frozen_string_literal: true

require 'unique_user_events'

module MyHealth
  module V1
    class PrescriptionsController < RxController
      include Filterable
      include MyHealth::PrescriptionHelper::Filtering
      include MyHealth::PrescriptionHelper::Sorting
      include MyHealth::RxGroupingHelper

      IN_PROGRESS_STATUSES = ['Active: Refill in Process', 'Active: Submitted'].freeze
      ACTIVE_STATUSES = [
        'Active', 'Active: Refill in Process', 'Active: Non-VA', 'Active: On Hold',
        'Active: Parked', 'Active: Submitted'
      ].freeze
      NON_ACTIVE_STATUSES = %w[Discontinued Expired Transferred Unknown].freeze

      # This index action supports various parameters described below, all are optional
      # This comment can be removed once documentation is finalized
      # @param refill_status - one refill status to filter on
      # @param page - the paginated page to fetch
      # @param per_page - the number of items to fetch per page
      # @param sort - the attribute to sort on, negated for descending, use sort[]= for multiple argument query params
      #        (ie: ?sort[]=refill_status&sort[]=-prescription_id)
      def index
        resource = collection_resource
        recently_requested = get_recently_requested_prescriptions(resource.data)
        all_medications_count = count_grouped_prescriptions(resource.data)
        resource.records = resource_data_modifications(resource)

        filter_metadata = build_filter_metadata(resource.data, all_medications_count)
        resource = apply_filters(resource) if params[:filter].present?
        resource = apply_sorting(resource, params[:sort])
        # Only move PD prescriptions to top when using default sort
        resource.records = sort_prescriptions_with_pd_at_top(resource.records) if params[:sort].blank?
        is_using_pagination = params[:page].present? || params[:per_page].present?
        resource = resource.paginate(**pagination_params) if is_using_pagination
        options = { meta: resource.metadata.merge(filter_metadata).merge(recently_requested:) }
        options[:links] = pagination_links(resource) if is_using_pagination
        UniqueUserEvents.log_event(user: current_user,
                                   event_name: UniqueUserEvents::EventRegistry::PRESCRIPTIONS_ACCESSED)
        render json: MyHealth::V1::PrescriptionDetailsSerializer.new(resource.records, options)
      rescue => e
        log_rx_controller_error('Rx prescriptions index failed', e)
        raise
      end

      def show
        id = params[:id].try(:to_i)
        all_data = collection_resource.data
        # Filter out discontinued non-VA meds before searching
        filtered_data = filter_discontinued_non_va_meds(all_data)
        resource = get_single_rx_from_grouped_list(filtered_data, id)
        raise Common::Exceptions::RecordNotFound, id if resource.blank?

        options = { meta: client.get_rx_details(id).metadata }
        render json: MyHealth::V1::PrescriptionDetailsSerializer.new(resource, options)
      rescue Common::Exceptions::RecordNotFound
        raise
      rescue => e
        log_rx_controller_error('Rx prescription show failed', e, prescription_id: params[:id])
        raise
      end

      def refill
        client.post_refill_rx(params[:id])

        # Log unique user event for prescription refill requested
        UniqueUserEvents.log_event(
          user: current_user,
          event_name: UniqueUserEvents::EventRegistry::PRESCRIPTIONS_REFILL_REQUESTED
        )

        head :no_content
      rescue => e
        log_rx_controller_error('Rx prescription refill failed', e, prescription_id: params[:id])
        raise
      end

      def filter_renewals(resource)
        resource.records = resource.data.select(&method(:renewable))
        resource.metadata = resource.metadata.merge({
                                                      'filter' => {
                                                        'disp_status' => {
                                                          'eq' => 'Active,Expired'
                                                        }
                                                      }
                                                    })
        resource
      end

      def refill_prescriptions
        ids = params[:ids]
        successful_ids = []
        failed_ids = []
        ids.each do |id|
          client.post_refill_rx(id)
          successful_ids << id
        rescue => e
          log_rx_controller_error('Rx batch refill failed for prescription', e, prescription_id: id)
          failed_ids << id
        end

        # Log unique user event for prescription refill requested
        UniqueUserEvents.log_event(
          user: current_user,
          event_name: UniqueUserEvents::EventRegistry::PRESCRIPTIONS_REFILL_REQUESTED
        )

        render json: { successful_ids:, failed_ids: }
      rescue => e
        log_rx_controller_error('Rx refill_prescriptions failed', e)
        raise
      end

      def list_refillable_prescriptions
        resource = collection_resource
        # Filter out discontinued non-VA meds before calculating metadata and refillability
        filtered_data = filter_discontinued_non_va_meds(resource.data)
        recently_requested = get_recently_requested_prescriptions(filtered_data)
        resource.records = filter_data_by_refill_and_renew(filtered_data)

        options = { meta: resource.metadata.merge(recently_requested:) }
        render json: MyHealth::V1::PrescriptionDetailsSerializer.new(resource.records, options)
      rescue => e
        log_rx_controller_error('Rx list refillable prescriptions failed', e)
        raise
      end

      private

      def log_rx_controller_error(message, error, extra = {})
        ids = Array.wrap(current_user.active_mhv_ids)
        Rails.logger.error(message, rx_controller_error_log_payload(error, ids).merge(extra))
      rescue => e
        Rails.logger.error(
          "#{message} (rx_controller_error_log_failed)",
          log_failure_class: e.class.name,
          log_failure_message: e.message.to_s,
          original_error_class: error.class.name,
          original_error_message: error.message.to_s
        )
      end

      def rx_controller_error_log_payload(error, ids)
        {
          user_icn: current_user.icn,
          mhv_correlation_id: current_user.mhv_correlation_id,
          active_mhv_ids_count: ids.size,
          multiple_active_mhv_ids: ids.size > 1,
          sign_in_service: current_user.identity&.sign_in&.dig(:service_name),
          error_class: error.class.name,
          error_message: error.message.to_s
        }
      end

      def get_recently_requested_prescriptions(data)
        data.select do |item|
          IN_PROGRESS_STATUSES.include?(item.disp_status)
        end
      end

      def filter_params
        @filter_params ||= begin
          valid_filter_params = params.require(:filter).permit(PrescriptionDetails.filterable_params)
          raise Common::Exceptions::FilterNotAllowed, params[:filter] if valid_filter_params.empty?

          valid_filter_params
        end
      end

      def apply_filters(resource)
        resource.metadata[:filter] = {}
        disp_status = filter_params[:disp_status]

        if disp_status.present?
          if disp_status[:eq]&.downcase == 'active,expired'.downcase
            filter_renewals(resource)
          else
            filters = disp_status[:eq].split(',').map(&:strip).map(&:downcase)
            resource.records = resource.data.select { |item| filters.include?(item.disp_status.downcase) }
            resource.metadata[:filter][:dispStatus] = { eq: disp_status[:eq] }
          end
        end
        resource
      end

      def collection_resource
        case params[:refill_status]
        when nil
          client.get_all_rxs
        when 'active'
          client.get_active_rxs_with_details
        end
      end

      def resource_data_modifications(resource)
        display_pending_meds = Flipper.enabled?(:mhv_medications_display_pending_meds, current_user)
        # according to business logic filter for all medications is the only list that should contain PD meds
        resource.records = if params[:filter].blank? && display_pending_meds
                             resource.data.reject { |item| item.prescription_source.equal? 'PF' }
                           else
                             # TODO: remove this line when PF and PD are allowed on va.gov
                             resource.records = remove_pf_pd(resource.data)
                           end
        # Filter out discontinued non-VA meds
        resource.records = filter_discontinued_non_va_meds(resource.records)
        resource.records = group_prescriptions(resource.records)
      end

      def build_filter_metadata(list, all_medications_count)
        {
          filter_count: {
            all_medications: all_medications_count,
            active: count_active_medications(list),
            recently_requested: count_recently_requested(list),
            renewal: list.count { |rx| renewable(rx) },
            non_active: count_non_active_medications(list)
          }
        }
      end

      def count_active_medications(list)
        list.count { |rx| ACTIVE_STATUSES.include?(rx.disp_status) }
      end

      def count_non_active_medications(list)
        list.count { |rx| NON_ACTIVE_STATUSES.include?(rx.disp_status) }
      end

      def count_recently_requested(list)
        list.count { |item| IN_PROGRESS_STATUSES.include?(item.disp_status) }
      end

      # TODO: remove once pf and pd are allowed on va.gov
      def remove_pf_pd(data)
        sources_to_remove_from_data = %w[PF PD]
        data.reject { |item| sources_to_remove_from_data.include?(item.prescription_source) }
      end

      def sort_prescriptions_with_pd_at_top(prescriptions)
        pd, others = prescriptions.partition { |med| med.prescription_source == 'PD' }
        pd + others
      end
    end
  end
end
