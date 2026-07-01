# frozen_string_literal: true

require 'unified_health_data/medical_records_service'
require 'unified_health_data/serializers/condition_serializer'
require 'unique_user_events'

module MyHealth
  module V2
    ##
    # V2 controller for health conditions served through the Unified Health Data
    # (UHD) Medical Records service. Supports sorting and surfaces partial-failure
    # warnings as 206 Partial Content responses.
    #
    class ConditionsController < ApplicationController
      include MyHealth::V2::Concerns::ErrorHandler
      include SortableRecords
      service_tag 'mhv-medical-records'

      ##
      # Lists the current user's health conditions, optionally sorted, and logs
      # unique-user access events.
      #
      # @return [JSON] serialized conditions; 206 Partial Content when warnings
      #   are present, otherwise 200 OK
      #
      def index
        @result = service.get_conditions(no_cache: no_cache_requested?)
        conditions = sort_records(@result[:records], params[:sort])
        opts = warnings_present? ? { meta: { warnings: @result[:warnings] } } : {}

        # Log unique user events for conditions accessed
        UniqueUserEvents.log_events(
          user: @current_user,
          event_names: [
            UniqueUserEvents::EventRegistry::MEDICAL_RECORDS_ACCESSED,
            UniqueUserEvents::EventRegistry::MEDICAL_RECORDS_CONDITIONS_ACCESSED
          ]
        )

        render json: UnifiedHealthData::Serializers::ConditionSerializer.new(conditions, opts),
               status: warnings_present? ? :partial_content : :ok
      rescue Common::Exceptions::GatewayTimeout,
             Common::Client::Errors::ClientError,
             Common::Exceptions::BackendServiceException,
             StandardError => e
        handle_error(e, resource_name: 'conditions', api_type: 'SCDF')
      end

      ##
      # Retrieves a single health condition by id.
      #
      # @return [JSON] serialized condition, or a 404 error envelope if not found
      #
      def show
        condition = service.get_single_condition(params[:id])
        unless condition
          render_error('Condition Not Found',
                       'The requested condition record was not found',
                       '404', 404, :not_found)
          return
        end
        serialized_condition = UnifiedHealthData::Serializers::ConditionSerializer.new(condition)
        render json: serialized_condition,
               status: :ok
      rescue Common::Exceptions::GatewayTimeout,
             Common::Client::Errors::ClientError,
             Common::Exceptions::BackendServiceException,
             StandardError => e
        handle_error(e, resource_name: 'conditions', api_type: 'FHIR')
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
