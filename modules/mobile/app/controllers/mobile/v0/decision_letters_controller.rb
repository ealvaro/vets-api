# frozen_string_literal: true

require 'claim_letters/claim_letter_downloader'
require 'va_profile/veteran_status/va_profile_error'

module Mobile
  module V0
    # Provides endpoints for retrieving and downloading VA decision letters.
    #
    # Decision letters are fetched from either Lighthouse Benefits Documents or
    # VBMS, controlled by the +:cst_claim_letters_use_lighthouse_api_provider_mobile+
    # Flipper flag.
    #
    # Upstream 5xx errors (500–504) and Breakers circuit-open exceptions are
    # rescued and translated into 502 Bad Gateway responses to prevent upstream
    # failures from surfacing as vets-api 500s in DataDog.
    #
    # @see LighthouseClaimLettersProvider
    # @see ClaimStatusTool::ClaimLetterDownloader
    # @see Mobile::V0::DecisionLetterSerializer
    class DecisionLettersController < ApplicationController
      before_action { authorize :bgs, :access? }

      # Upstream 5xx errors from Lighthouse/VBMS that should never surface as vets-api 500s.
      # These are gateway-level failures — the upstream service is down or misbehaving,
      # not vets-api itself.
      UPSTREAM_ERRORS = [
        Common::Exceptions::ExternalServerInternalServerError, # LH 500
        Common::Exceptions::BadGateway,                        # LH 502
        Common::Exceptions::ServiceUnavailable,                # LH 503
        Common::Exceptions::GatewayTimeout,                    # LH 504
        Breakers::OutageException,                             # Breakers circuit open
        VAProfile::VeteranStatus::VAProfileError               # VA Profile failure during error logging
      ].freeze

      # Returns a list of decision letters for the authenticated veteran.
      #
      # GET /mobile/v0/claims/decision-letters
      #
      # @return [JSON] serialized list of {Mobile::V0::DecisionLetterSerializer} records
      def index
        response = service.get_letters
        list = if Flipper.enabled?(:cst_claim_letters_use_lighthouse_api_provider_mobile, @current_user)
                 lighthouse_decision_letters_adapter.parse(response)
               else
                 decision_letters_adapter.parse(response)
               end
        log_decision_letters(list) if Flipper.enabled?(:mobile_claims_log_decision_letter_sent)

        render json: Mobile::V0::DecisionLetterSerializer.new(list)
      rescue *UPSTREAM_ERRORS => e
        translate_lighthouse_server_error!(e, '#index')
      end

      # Downloads a single decision letter by document ID.
      #
      # GET /mobile/v0/claims/decision-letters/:document_id/download
      #
      # @param document_id [String] URL-encoded document identifier
      # @return [Binary] the letter PDF streamed as an attachment
      def download
        document_id = CGI.unescape(params[:document_id])
        service.get_letter(document_id) do |data, mime_type, disposition, filename|
          send_data(data, type: mime_type, disposition:, filename:)
        end
      rescue *UPSTREAM_ERRORS => e
        translate_lighthouse_server_error!(e, '#download')
      end

      private

      # Logs decision letter metadata for monitoring purposes.
      #
      # @param list [Array] parsed decision letter records
      def log_decision_letters(list)
        return nil if list.empty?

        monitor.track_request(
          :info,
          'MOBILE DECISION LETTERS COUNT',
          'mobile.decision_letters.count',
          user_uuid: @current_user.uuid,
          decision_letter_sent_count: list.count,
          decision_letter_doc_type: list.map(&:doc_type),
          filtered_out_doc_type27: Flipper.enabled?(:mobile_filter_doc_27_decision_letters_out)
        )
      end

      # @return [Mobile::V0::Adapters::DecisionLetters]
      def decision_letters_adapter
        Mobile::V0::Adapters::DecisionLetters.new
      end

      # @return [Mobile::V0::Adapters::LighthouseDecisionLetters]
      def lighthouse_decision_letters_adapter
        Mobile::V0::Adapters::LighthouseDecisionLetters.new
      end

      # Returns the appropriate service provider based on the Flipper flag.
      #
      # @return [LighthouseClaimLettersProvider, ClaimStatusTool::ClaimLetterDownloader]
      def service
        if Flipper.enabled?(:cst_claim_letters_use_lighthouse_api_provider_mobile, @current_user)
          LighthouseClaimLettersProvider.new(@current_user)
        else
          ClaimStatusTool::ClaimLetterDownloader.new(@current_user)
        end
      end

      # Translates upstream 5xx errors into 502 Bad Gateway when the Lighthouse
      # provider is active. Re-raises the original error otherwise.
      #
      # @param error [Exception] the caught upstream exception
      # @param source [String] action identifier (e.g. "#index", "#download")
      # @raise [Common::Exceptions::BadGateway] when Lighthouse flag is enabled
      def translate_lighthouse_server_error!(error, source)
        if Flipper.enabled?(:cst_claim_letters_use_lighthouse_api_provider_mobile, @current_user)
          raise Common::Exceptions::BadGateway.new(
            detail: error.message,
            source: "DecisionLettersController#{source}"
          )
        end

        raise
      end

      # @return [Logging::Monitor]
      def monitor
        @monitor ||= Logging::Monitor.new(
          'mobile-decision-letters',
          allowlist: %i[
            user_uuid
            decision_letter_sent_count
            decision_letter_doc_type
            filtered_out_doc_type27
          ]
        )
      end
    end
  end
end
