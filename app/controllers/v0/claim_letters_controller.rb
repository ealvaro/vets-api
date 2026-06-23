# frozen_string_literal: true

require 'claim_letters/claim_letter_downloader'
require 'claim_letters/providers/claim_letters/lighthouse_claim_letters_provider'
require 'logging/monitor'
require 'va_profile/veteran_status/va_profile_error'

module V0
  class ClaimLettersController < ApplicationController
    before_action :set_api_provider

    service_tag 'claim-status'

    VBMS_LIGHTHOUSE_MIGRATION_STATSD_KEY_PREFIX = 'vbms_lighthouse_claim_letters_provider_error'

    # GET /v0/claim_letters
    # Returns claim decision letters for the current user.
    def index
      docs = service.get_letters
      log_metadata_to_datadog(docs)
      log_letter_count(docs)
      log_stale_or_empty_letters(docs)

      render json: docs
    rescue Common::Exceptions::ExternalServerInternalServerError => e
      log_api_provider_error(e)
      raise_upstream_bad_gateway
    rescue VAProfile::VeteranStatus::VAProfileError => e
      log_upstream_va_profile_error(e)
      raise_upstream_bad_gateway
    rescue Common::Exceptions::BaseError
      raise
    rescue => e
      log_application_error(e)
      raise
    end

    # GET /v0/claim_letters/:document_id
    # Streams PDF content for a single claim letter.
    def show
      document_id = CGI.unescape(params[:document_id])

      service.get_letter(document_id) do |data, mime_type, disposition, filename|
        send_data(data, type: mime_type, disposition:, filename:)
      end
    rescue Common::Exceptions::ExternalServerInternalServerError => e
      log_api_provider_error(e)
      raise_upstream_bad_gateway
    rescue VAProfile::VeteranStatus::VAProfileError => e
      log_upstream_va_profile_error(e)
      raise_upstream_bad_gateway
    rescue Common::Exceptions::BaseError
      raise
    rescue => e
      log_application_error(e)
      raise
    end

    private

    def set_api_provider
      @use_lighthouse = Flipper.enabled?(:cst_claim_letters_use_lighthouse_api_provider, @current_user)
      @api_provider = @use_lighthouse ? 'lighthouse' : 'VBMS'
    end

    def service
      monitor.track_request(:info,
                            'Choosing Claim Letters API Provider via cst_claim_letters_use_lighthouse_api_provider',
                            'claim_letters.api_provider',
                            message_type: 'cst.api_provider', api_provider: @api_provider, action: action_name)
      Datadog::Tracing.active_trace&.set_tag('api_provider', @api_provider)
      if @use_lighthouse
        LighthouseClaimLettersProvider.new(@current_user)
      else
        ClaimStatusTool::ClaimLetterDownloader.new(@current_user)
      end
    end

    def log_metadata_to_datadog(docs)
      docs_metadata = docs.map { |d| { doc_type: d[:doc_type], type_description: d[:type_description] } }
      monitor.track_request(:info, 'DDL Document Types Metadata', 'claim_letters.doctypes_metadata',
                            message_type: 'ddl.doctypes_metadata', document_type_metadata: docs_metadata)
    end

    def log_letter_count(docs)
      ::Rails.logger.info('Claim letters count', {
                            message_type: 'cst.claim_letters.count',
                            letter_count: docs.size,
                            api_provider: @api_provider
                          })
    end

    def log_stale_or_empty_letters(docs)
      return unless Flipper.enabled?(:cst_claim_letters_log_stale_or_empty, @current_user)

      decision_letters = docs&.select { |d| d[:doc_type] == '184' }
      newest_letter_date = decision_letters&.filter_map { |d| d[:received_at].presence&.to_datetime }&.max
      no_letters = decision_letters.blank?
      all_stale = !no_letters && (newest_letter_date.nil? || newest_letter_date < 1.day.ago)

      return unless no_letters || all_stale

      ::Rails.logger.info('Claim letters stale or empty for user', {
                            message_type: 'cst.claim_letters.stale_or_empty',
                            user_uuid: @current_user.uuid,
                            user_account_uuid: @current_user.user_account_uuid,
                            letter_count: decision_letters&.size,
                            newest_letter_date: newest_letter_date&.iso8601,
                            reason: no_letters ? 'no_letters' : 'all_stale'
                          })
    end

    def log_api_provider_error(error)
      monitor.track_request(:warn, error.message,
                            "#{VBMS_LIGHTHOUSE_MIGRATION_STATSD_KEY_PREFIX}.#{action_name}.#{@api_provider}",
                            message_type: 'cst.api_provider.error', api_provider: @api_provider, action: action_name)
    end

    def log_application_error(error)
      monitor.track_request(:error,
                            error.message,
                            "claim_letters.application_error.#{action_name}",
                            action: action_name)
    end

    def log_upstream_va_profile_error(error)
      monitor.track_request(:warn,
                            'VAProfile VeteranStatus error during claim letters request',
                            "claim_letters.va_profile_error.#{action_name}",
                            action: action_name,
                            va_profile_status: error.status)
    end

    # Maps upstream server errors (Lighthouse/VBMS 500s) to 502 Bad Gateway so they don't
    # surface as application-level 500s in Datadog. The upstream service failed, not our app.
    def raise_upstream_bad_gateway
      error = Common::Exceptions::SerializableError.new(
        status: '502',
        title: 'Bad Gateway',
        detail: "Upstream service (#{@api_provider}) returned an internal server error",
        code: '502'
      )
      raise Common::Exceptions::BadGateway.new(errors: [error])
    end

    def monitor
      @monitor ||= Logging::Monitor.new('claim-letters', allowlist: %i[
                                          api_provider action document_type_metadata message_type va_profile_status
                                        ])
    end
  end
end
