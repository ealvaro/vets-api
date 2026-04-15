# frozen_string_literal: true

require 'unified_health_data/service'
require 'unified_health_data/serializers/allergy_serializer'
require 'unique_user_events'

module MyHealth
  module V2
    class AllergiesController < ApplicationController
      include MyHealth::V2::Concerns::ErrorHandler
      include SortableRecords
      service_tag 'mhv-medical-records'

      def index
        @result = service.get_allergies
        allergies = sort_records(@result[:records], params[:sort])
        opts = warnings_present? ? { meta: { warnings: @result[:warnings] } } : {}
        serialized_allergies = UnifiedHealthData::AllergySerializer.new(allergies, opts)

        # Log unique user events for allergies accessed
        UniqueUserEvents.log_events(
          user: @current_user,
          event_names: [
            UniqueUserEvents::EventRegistry::MEDICAL_RECORDS_ACCESSED,
            UniqueUserEvents::EventRegistry::MEDICAL_RECORDS_ALLERGIES_ACCESSED
          ]
        )

        render json: serialized_allergies,
               status: warnings_present? ? :partial_content : :ok
      rescue Common::Exceptions::GatewayTimeout,
             Common::Client::Errors::ClientError,
             Common::Exceptions::BackendServiceException,
             StandardError => e
        handle_error(e, resource_name: 'allergies', api_type: 'SCDF')
      end

      def show
        allergy = service.get_single_allergy(params['id'])
        unless allergy
          render_error('Record Not Found',
                       'The requested record was not found',
                       '404', 404, :not_found)
          return
        end
        serialized_allergy = UnifiedHealthData::AllergySerializer.new(allergy)
        render json: serialized_allergy,
               status: :ok
      rescue Common::Exceptions::GatewayTimeout,
             Common::Client::Errors::ClientError,
             Common::Exceptions::BackendServiceException,
             StandardError => e
        handle_error(e, resource_name: 'allergies', api_type: 'FHIR')
      end

      private

      def warnings_present?
        @warnings_present ||= @result[:warnings].present?
      end

      def service
        @service ||= UnifiedHealthData::Service.new(@current_user)
      end
    end
  end
end
