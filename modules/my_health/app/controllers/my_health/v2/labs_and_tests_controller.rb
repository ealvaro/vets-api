# frozen_string_literal: true

require 'unified_health_data/medical_records_service'
require 'unified_health_data/serializers/lab_or_test_serializer'
require 'unique_user_events'

module MyHealth
  module V2
    class LabsAndTestsController < ApplicationController
      include MyHealth::V2::Concerns::ErrorHandler
      include SortableRecords
      service_tag 'mhv-medical-records'

      def index
        @result = service.get_labs(start_date: params[:start_date], end_date: params[:end_date], caller: 'web_v2')
        labs = sort_records(@result[:records], params[:sort])
        opts = warnings_present? ? { meta: { warnings: @result[:warnings] } } : {}
        serialized_labs = UnifiedHealthData::Serializers::LabOrTestSerializer.new(labs, opts)

        UniqueUserEvents.log_events(
          user: @current_user,
          event_names: [
            UniqueUserEvents::EventRegistry::MEDICAL_RECORDS_ACCESSED,
            UniqueUserEvents::EventRegistry::MEDICAL_RECORDS_LABS_ACCESSED
          ]
        )

        render json: serialized_labs,
               status: warnings_present? ? :partial_content : :ok
      rescue Common::Exceptions::NotImplemented
        raise
      rescue Common::Exceptions::GatewayTimeout,
             Common::Client::Errors::ClientError,
             Common::Exceptions::BackendServiceException,
             StandardError => e
        handle_error(e, resource_name: 'labs and tests', api_type: 'SCDF')
      end

      private

      def service
        @service ||= UnifiedHealthData::MedicalRecordsService.new(@current_user)
      end

      def warnings_present?
        @warnings_present ||= @result[:warnings].present?
      end
    end
  end
end
