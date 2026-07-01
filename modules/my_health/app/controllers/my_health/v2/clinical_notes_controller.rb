# frozen_string_literal: true

require 'unified_health_data/medical_records_service'
require 'unified_health_data/serializers/clinical_notes_serializer'
require 'unique_user_events'

module MyHealth
  module V2
    ##
    # V2 controller for clinical notes (care summaries and notes) served through
    # the Unified Health Data (UHD) Medical Records service. Supports date-range
    # filtering and sorting; single-note lookup requires an Oracle Health source.
    #
    class ClinicalNotesController < ApplicationController
      include MyHealth::V2::Concerns::ErrorHandler
      include SortableRecords
      service_tag 'mhv-medical-records'
      before_action :validate_source_param, only: :show

      ##
      # Lists the current user's clinical notes within an optional date range,
      # optionally sorted, and logs unique-user access events.
      #
      # @return [JSON] serialized clinical notes; 206 Partial Content when
      #   warnings are present, otherwise 200 OK
      #
      def index
        @result = service.get_care_summaries_and_notes(start_date: params[:start_date], end_date: params[:end_date],
                                                       no_cache: no_cache_requested?)
        care_notes = sort_records(@result[:records], params[:sort])
        opts = warnings_present? ? { meta: { warnings: @result[:warnings] } } : {}

        UniqueUserEvents.log_events(
          user: @current_user,
          event_names: [
            UniqueUserEvents::EventRegistry::MEDICAL_RECORDS_ACCESSED,
            UniqueUserEvents::EventRegistry::MEDICAL_RECORDS_NOTES_ACCESSED
          ]
        )

        render json: UnifiedHealthData::Serializers::ClinicalNotesSerializer.new(care_notes, opts),
               status: warnings_present? ? :partial_content : :ok
      rescue ArgumentError => e
        render_error('Invalid Parameter', e.message, '400', 400, :bad_request)
      rescue Common::Exceptions::GatewayTimeout,
             Common::Client::Errors::ClientError,
             Common::Exceptions::BackendServiceException,
             StandardError => e
        handle_error(e, resource_name: 'clinical notes', api_type: 'SCDF')
      end

      ##
      # Retrieves a single clinical note by id and source.
      #
      # @return [JSON] serialized clinical note, or a 404 error envelope if not found
      #
      def show
        care_note = service.get_single_summary_or_note(params['id'], source: params['source'])
        if care_note.nil?
          render_error('Record Not Found',
                       'The requested record was not found',
                       '404', 404, :not_found)
          return
        end
        serialized_note = UnifiedHealthData::Serializers::ClinicalNotesSerializer.new(care_note)
        render json: serialized_note,
               status: :ok
      rescue Common::Exceptions::GatewayTimeout,
             Common::Client::Errors::ClientError,
             Common::Exceptions::BackendServiceException,
             StandardError => e
        handle_error(e, resource_name: 'clinical notes', api_type: 'FHIR')
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

      def valid_sources
        [UnifiedHealthData::SourceConstants::ORACLE_HEALTH, UnifiedHealthData::SourceConstants::VISTA]
      end

      def validate_source_param
        source = params['source']

        if source.blank?
          render_error('Record Not Found',
                       'The requested record was not found. A source parameter is required.',
                       '400', 400, :bad_request)
        elsif source == UnifiedHealthData::SourceConstants::VISTA
          render_error('Invalid Parameter',
                       'VistA notes are not available for direct lookup. Use source=oracle-health.',
                       '400', 400, :bad_request)
        elsif !valid_source?(source)
          render_error('Invalid Parameter',
                       "Invalid source: '#{source}'. Must be one of: #{valid_sources.join(', ')}",
                       '400', 400, :bad_request)
        end
      end

      def valid_source?(source)
        valid_sources.include?(source)
      end
    end
  end
end
