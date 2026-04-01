# frozen_string_literal: true

require 'unified_health_data/service'
require 'unified_health_data/serializers/vital_serializer'

module MyHealth
  module V2
    class VitalsController < ApplicationController
      include MyHealth::V2::Concerns::ErrorHandler
      include SortableRecords
      service_tag 'mhv-medical-records'

      def index
        @result = service.get_vitals
        vitals = sort_records(@result[:records], params[:sort])
        opts = warnings_present? ? { meta: { warnings: @result[:warnings] } } : {}

        serialized_vitals = UnifiedHealthData::VitalSerializer.new(vitals, opts)
        render json: serialized_vitals,
               status: warnings_present? ? :partial_content : :ok
      rescue Common::Client::Errors::ClientError,
             Common::Exceptions::BackendServiceException,
             StandardError => e
        handle_error(e, resource_name: 'vitals', api_type: 'SCDF')
      end

      private

      def service
        @service ||= UnifiedHealthData::Service.new(@current_user)
      end

      def warnings_present?
        @warnings_present ||= @result[:warnings].present?
      end
    end
  end
end
