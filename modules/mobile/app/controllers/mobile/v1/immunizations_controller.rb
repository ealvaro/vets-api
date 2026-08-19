# frozen_string_literal: true

require 'unique_user_events'
require 'unified_health_data/medical_records_service'
require 'unified_health_data/serializers/immunization_serializer'

module Mobile
  module V1
    ##
    # Mobile (v1) controller for a Veteran's immunization records.
    #
    # Reads from the Unified Health Data (UHD) Medical Records service. Tags the
    # active Datadog span with the data source, sorts ascending by date, and
    # returns pagination metadata for backwards compatibility with the mobile
    # frontend.
    #
    class ImmunizationsController < ApplicationController
      include MedicalRecords::ErrorHandler

      service_tag 'mhv-medical-records'

      FUTURE_DATE = '3000-01-01'

      ##
      # Lists the current user's immunizations from UHD, sorted by
      # date, and logs unique-user access events.
      #
      # @return [JSON] serialized immunizations with pagination metadata
      #
      def index
        tag_data_source_span('uhd')

        records = fetch_uhd_immunizations
        return if performed? # ErrorHandler already rendered a response

        log_immunization_access

        # Sort in ascending order to send to the FE
        # Handle nil dates by sorting at the end of the list
        sorted = records.sort_by { |item| item.date || FUTURE_DATE }

        render json: serialize_immunizations(sorted),
               status: :ok
      end

      private

      # Fetches immunizations from UHD, with MedicalRecords::ErrorHandler rescue.
      # Errors on the UHD path get structured JSON envelopes from the ErrorHandler.
      def fetch_uhd_immunizations
        result = uhd_service.get_immunizations
        # Warnings (e.g., Partial Failure responses from SCDF) are not surfaced to the mobile app.
        # Mobile has its own release cycle; warning support can be added separately if needed.
        # For now, just grab the records and return them
        result[:records]
      rescue Common::Exceptions::GatewayTimeout,
             Common::Client::Errors::ClientError,
             Common::Exceptions::BackendServiceException,
             StandardError => e
        handle_error(e, resource_name: 'Mobile immunizations', api_type: 'Mobile UHD')
      end

      # Grab the active Datadog APM span and
      # set a custom tag medical_records.data_source to "uhd".
      def tag_data_source_span(data_source)
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
        meta = { # Hardcode pagination for backwards compatibility in the app FE
          pagination: {
            current_page: 1,
            per_page: 5000,
            total_pages: 1,
            total_entries: immunizations.length
          }
        }
        UnifiedHealthData::Serializers::ImmunizationSerializer.new(immunizations, meta:)
      end

      def uhd_service
        @uhd_service ||= UnifiedHealthData::MedicalRecordsService.new(@current_user)
      end
    end
  end
end
