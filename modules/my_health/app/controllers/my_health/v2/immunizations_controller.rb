# frozen_string_literal: true

require 'lighthouse/veterans_health/client'
require 'lighthouse/veterans_health/models/immunization'
require 'lighthouse/veterans_health/serializers/immunization_serializer'
require 'unified_health_data/medical_records_service'
require 'unified_health_data/serializers/immunization_serializer'
require 'common/client/errors'
require 'common/exceptions'
require 'unique_user_events'

module MyHealth
  module V2
    ##
    # V2 controller for immunization (vaccine) records.
    #
    # Reads from the Unified Health Data (UHD) Medical Records service when the
    # +:mhv_accelerated_delivery_vaccines_enabled+ flag is on, otherwise falls
    # back to the Lighthouse Veterans Health API. Tags the active Datadog span
    # with the selected data source and emits StatsD/unique-user metrics.
    #
    class ImmunizationsController < ApplicationController
      include MyHealth::V2::Concerns::ErrorHandler
      include SortableRecords
      service_tag 'mhv-medical-records'

      STATSD_KEY_PREFIX = 'api.my_health.immunizations'

      ##
      # Lists the current user's immunizations from UHD or Lighthouse, records
      # metrics, and logs unique-user access events.
      #
      # @return [JSON] serialized immunizations; 206 Partial Content when UHD
      #   warnings are present, otherwise 200 OK
      #
      def index
        tag_datadog_data_source(uhd_enabled? ? 'uhd' : 'lighthouse')

        if uhd_enabled?
          @result = uhd_service.get_immunizations
          immunizations = sort_records(@result[:records], params[:sort])
          opts = warnings_present? ? { meta: { warnings: @result[:warnings] } } : {}
          log_vaccines(immunizations.length)
          render json: UnifiedHealthData::Serializers::ImmunizationSerializer.new(immunizations, opts),
                 status: warnings_present? ? :partial_content : :ok
        else
          response = client.get_immunizations
          immunizations = Lighthouse::VeteransHealth::Serializers::ImmunizationSerializer
                          .from_fhir_bundle(response.body)

          log_vaccines(immunizations.length)
          render json: { data: immunizations }
        end
      rescue Common::Exceptions::GatewayTimeout,
             Common::Client::Errors::ClientError,
             Common::Exceptions::BackendServiceException,
             StandardError => e
        handle_error(e, resource_name: 'immunization records', api_type: uhd_enabled? ? 'SCDF' : 'FHIR')
      end

      ##
      # Retrieves a single immunization by id.
      #
      # Until SCDF offers a get-by-id endpoint, this only returns Lighthouse records.
      #
      # @return [JSON] serialized immunization, or a 404 error envelope if not found
      #
      def show
        id = params[:id]
        begin
          response = client.get_immunizations
          immunization = response.body['entry'].find { |entry| entry['resource']['id'] == id }

          unless immunization
            render_error('Immunization Not Found',
                         'The requested immunization record was not found',
                         '404', 404, :not_found)
            return
          end

          return_value = Lighthouse::VeteransHealth::Serializers::ImmunizationSerializer
                         .from_fhir(immunization['resource'])

          render json: { data: return_value }
        rescue Common::Exceptions::GatewayTimeout,
               Common::Client::Errors::ClientError,
               Common::Exceptions::BackendServiceException,
               StandardError => e
          handle_error(e, resource_name: 'immunization records', api_type: 'FHIR')
        end
      end

      private

      # Grab the active Datadog APM span and
      # set a custom tag medical_records.data_source to either "uhd" or "lighthouse".
      def tag_datadog_data_source(data_source)
        span = Datadog::Tracing.active_span
        span&.set_tag('medical_records.data_source', data_source)
      end

      def uhd_enabled?
        return @uhd_enabled if defined?(@uhd_enabled)

        @uhd_enabled = Flipper.enabled?(:mhv_accelerated_delivery_vaccines_enabled, current_user)
      end

      def log_vaccines(vaccines_count)
        # Track the number of immunizations returned to the client
        StatsD.gauge("#{STATSD_KEY_PREFIX}.count", vaccines_count)

        # Log unique user events for immunizations/vaccines accessed
        UniqueUserEvents.log_events(
          user: current_user,
          event_names: [
            UniqueUserEvents::EventRegistry::MEDICAL_RECORDS_ACCESSED,
            UniqueUserEvents::EventRegistry::MEDICAL_RECORDS_VACCINES_ACCESSED
          ]
        )
      end

      def client
        @client ||= Lighthouse::VeteransHealth::Client.new(current_user.icn)
      end

      def uhd_service
        @uhd_service ||= UnifiedHealthData::MedicalRecordsService.new(current_user)
      end

      def warnings_present?
        @warnings_present ||= @result[:warnings].present?
      end
    end
  end
end
