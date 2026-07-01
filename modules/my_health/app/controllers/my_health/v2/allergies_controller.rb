# frozen_string_literal: true

require 'unified_health_data/medical_records_service'
require 'unified_health_data/serializers/allergy_serializer'
require 'unique_user_events'

module MyHealth
  module V2
    ##
    # V2 controller for allergy records served through the Unified Health Data
    # (UHD) Medical Records service, which aggregates VistA and Oracle Health
    # data. Supports sorting and surfaces partial-failure warnings as 206
    # Partial Content responses.
    #
    class AllergiesController < ApplicationController
      include MyHealth::V2::Concerns::ErrorHandler
      include SortableRecords
      service_tag 'mhv-medical-records'

      ##
      # Lists the current user's allergies, optionally sorted, and logs
      # unique-user access events.
      #
      # @return [JSON] serialized allergies; 206 Partial Content when warnings
      #   are present, otherwise 200 OK
      #
      def index
        @result = service.get_allergies(no_cache: no_cache_requested?)
        allergies = sort_records(@result[:records], params[:sort])
        opts = warnings_present? ? { meta: { warnings: @result[:warnings] } } : {}
        serialized_allergies = UnifiedHealthData::Serializers::AllergySerializer.new(allergies, opts)

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

      ##
      # Retrieves a single allergy by id.
      #
      # @return [JSON] serialized allergy, or a 404 error envelope if not found
      #
      def show
        allergy = service.get_single_allergy(params['id'])
        unless allergy
          render_error('Record Not Found',
                       'The requested record was not found',
                       '404', 404, :not_found)
          return
        end
        serialized_allergy = UnifiedHealthData::Serializers::AllergySerializer.new(allergy)
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

      def no_cache_requested?
        ActiveModel::Type::Boolean.new.cast(params[:no_cache]) || false
      end

      def service
        @service ||= UnifiedHealthData::MedicalRecordsService.new(@current_user)
      end
    end
  end
end
