# frozen_string_literal: true

require 'unique_user_events'
require 'unified_health_data/medical_records_service'
require 'unified_health_data/serializers/immunization_serializer'

module Mobile
  module V1
    class ImmunizationsController < ApplicationController
      service_tag 'mhv-medical-records'

      FUTURE_DATE = '3000-01-01'

      def index
        data_source = uhd_enabled? ? 'uhd' : 'lighthouse'
        tag_datadog_span(data_source)

        if uhd_enabled?
          result = uhd_service.get_immunizations
          # Warnings (e.g., Partial Failure responses from SCDF) are not surfaced to the mobile app.
          # Mobile has its own release cycle; warning support can be added separately if needed.
          # For now, just grab the records and return them
          records = result[:records]
        else
          records = lh_immunizations
        end

        log_immunization_access

        # Sort in ascending order to send to the FE
        # Handle nil dates by sorting at the end of the list
        sorted = records.sort_by { |item| item.date || FUTURE_DATE }

        render json: serialize_immunizations(sorted),
               status: :ok
      end

      private

      def uhd_enabled?
        return @uhd_enabled if defined?(@uhd_enabled)

        @uhd_enabled = Flipper.enabled?(:mhv_accelerated_delivery_vaccines_enabled, current_user)
      end

      # Grab the active Datadog APM span and
      # set a custom tag medical_records.data_source to either "uhd" or "lighthouse".
      def tag_datadog_span(data_source)
        span = Datadog::Tracing.active_span
        span&.set_tag('medical_records.data_source', data_source)
      end

      def log_immunization_access
        UniqueUserEvents.log_events(
          user: @current_user,
          event_names: [
            UniqueUserEvents::EventRegistry::MEDICAL_RECORDS_ACCESSED,
            UniqueUserEvents::EventRegistry::MEDICAL_RECORDS_VACCINES_ACCESSED
          ]
        )
      end

      def serialize_immunizations(immunizations)
        if uhd_enabled?
          # Hardcode pagination for backwards compatibility in the app FE
          meta = {
            pagination: {
              current_page: 1,
              per_page: 5000,
              total_pages: 1,
              total_entries: immunizations.length
            }
          }
          UnifiedHealthData::Serializers::ImmunizationSerializer.new(immunizations, meta:)
        else
          paginated_immunizations, meta =
            Mobile::PaginationHelper.paginate(list: immunizations, validated_params: pagination_params)
          Mobile::V0::ImmunizationSerializer.new(paginated_immunizations, meta)
        end
      end

      def immunizations_adapter
        Mobile::V0::Adapters::Immunizations.new
      end

      def service
        Mobile::V0::LighthouseHealth::Service.new(@current_user)
      end

      def uhd_service
        @uhd_service ||= UnifiedHealthData::MedicalRecordsService.new(@current_user)
      end

      def pagination_params
        @pagination_params ||= Mobile::V0::Contracts::Immunizations.new.call(
          page_number: params.dig(:page, :number),
          page_size: params.dig(:page, :size),
          use_cache: use_cache_param
        )
      end

      def use_cache_param
        return true unless params.key?(:useCache)

        ActiveModel::Type::Boolean.new.cast(params[:useCache])
      end

      def lh_immunizations
        immunizations = Mobile::V0::Immunization.get_cached(@current_user) if pagination_params[:use_cache]

        unless immunizations
          immunizations = immunizations_adapter.parse(service.get_immunizations)
          Mobile::V0::Immunization.set_cached(@current_user, immunizations)
        end

        immunizations
      end
    end
  end
end
