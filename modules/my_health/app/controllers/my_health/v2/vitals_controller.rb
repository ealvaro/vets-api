# frozen_string_literal: true

require 'unified_health_data/medical_records_service'
require 'unified_health_data/serializers/vital_serializer'

module MyHealth
  module V2
    ##
    # V2 controller for vital signs served through the Unified Health Data (UHD)
    # Medical Records service. Supports sorting and surfaces partial-failure
    # warnings as 206 Partial Content responses.
    #
    class VitalsController < ApplicationController
      include MyHealth::V2::Concerns::ErrorHandler
      include SortableRecords
      service_tag 'mhv-medical-records'

      ##
      # Lists the current user's vitals, optionally sorted.
      #
      # @return [JSON] serialized vitals; 206 Partial Content when warnings are
      #   present, otherwise 200 OK
      #
      def index
        @result = service.get_vitals(no_cache: no_cache_requested?)
        vitals = sort_records(@result[:records], params[:sort])
        opts = warnings_present? ? { meta: { warnings: @result[:warnings] } } : {}

        serialized_vitals = UnifiedHealthData::Serializers::VitalSerializer.new(vitals, opts)
        render json: serialized_vitals,
               status: warnings_present? ? :partial_content : :ok
      rescue Common::Exceptions::GatewayTimeout,
             Common::Client::Errors::ClientError,
             Common::Exceptions::BackendServiceException,
             StandardError => e
        handle_error(e, resource_name: 'vitals', api_type: 'SCDF')
      end

      private

      def service
        @service ||= UnifiedHealthData::MedicalRecordsService.new(@current_user)
      end

      def no_cache_requested?
        ActiveModel::Type::Boolean.new.cast(params[:no_cache]) || false
      end

      def warnings_present?
        @warnings_present ||= @result[:warnings].present?
      end
    end
  end
end
