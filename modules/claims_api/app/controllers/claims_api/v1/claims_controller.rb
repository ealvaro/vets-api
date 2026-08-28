# frozen_string_literal: true

require 'evss/error_middleware'
require 'claims_api/evss_bgs_mapper'

module ClaimsApi
  module V1
    class ClaimsController < ApplicationController
      INVALID_CLAIM_ACCESS_DETAIL = 'Invalid claim ID for the veteran identified.'
      include ClaimsApi::PoaVerification

      before_action { permit_scopes %w[claim.read] }
      before_action :verify_power_of_attorney_relationship!, if: :header_request?

      # returns a list of claims for the veteran via their participant_id
      def index
        claims = claims_status_service.all(target_veteran.participant_id)
        raise_claim_not_found!('claims_v1_index') if claims == []

        render json: ClaimsApi::ClaimListSerializer.new(claims)
      rescue EVSS::ErrorMiddleware::EVSSError => e
        raise_claim_not_found!('claims_index', message: e.message)
      end

      # returns a single claim for a veteran via their lighthouse claim id or evss claim id.
      # If the claim is not found in the lighthouse database, it will attempt to find it in
      # BGS and validate access for the veteran via the participant id match.
      def show
        claim = ClaimsApi::AutoEstablishedClaim.get_by_id_and_icn(params[:id], target_veteran&.mpi&.icn)
        claim_show_response(claim)
      rescue => e
        show_error_response(e)
      end

      private

      def verify_power_of_attorney_relationship!
        return unless verify_power_of_attorney! == false

        claims_v1_logging(
          'claims',
          message: ClaimsApi::PoaVerification::REPRESENTATIVE_NOT_AUTHORIZED_FOR_VETERAN_ERROR_MESSAGE
        )
        raise ::Common::Exceptions::Unauthorized,
              detail: ClaimsApi::PoaVerification::REPRESENTATIVE_NOT_AUTHORIZED_FOR_VETERAN_ERROR_MESSAGE
      end

      def claim_show_response(claim)
        if claim && claim.status == 'errored'
          fetch_errored(claim)
        elsif claim && claim.evss_id.blank?
          render json: ClaimsApi::AutoEstablishedClaimSerializer.new(claim)
        elsif claim && claim.evss_id.present?
          updated_claim = claims_status_service.update_from_remote(claim.evss_id)
          render json: ClaimsApi::ClaimDetailSerializer.new(updated_claim, { params: { uuid: claim.id } })
        elsif /^\d{2,20}$/.match?(params[:id])
          bgs_claim = claims_status_service.find_benefit_claim_details_by_benefit_claim_id(params[:id])
          validate_bgs_participant!(bgs_claim)
          claim = claims_status_service.transform_bgs_claim_to_evss(bgs_claim)
          # NOTE: source doesn't seem to be accessible within a remote evss_claim
          render json: ClaimsApi::ClaimDetailSerializer.new(claim)
        else
          raise_claim_not_found!('claims_show')
        end
      end

      def show_error_response(error)
        unless error.is_a?(::Common::Exceptions::ResourceNotFound)
          claims_v1_logging('claims_show', message: error.message)
        end
        raise if error.is_a?(::Common::Exceptions::UnprocessableEntity)

        if invalid_claim_access_error?(error)
          raise_claim_not_found!('claims_show', message: INVALID_CLAIM_ACCESS_DETAIL)
        else
          raise_claim_not_found!('claims_show')
        end
      end

      # always raises 'Claim not found' for user, but logs invalid access message for Datadog logs
      def raise_claim_not_found!(endpoint, message: 'Claim not found')
        claims_v1_logging(endpoint, message:)
        raise ::Common::Exceptions::ResourceNotFound.new(detail: 'Claim not found')
      end

      def invalid_claim_access_error?(error)
        error.is_a?(::Common::Exceptions::ResourceNotFound) &&
          error.errors[0]&.detail == INVALID_CLAIM_ACCESS_DETAIL
      end

      def fetch_errored(claim)
        if claim.evss_response&.any?
          errors = format_evss_errors(claim.evss_response)
          raise ::Common::Exceptions::UnprocessableEntity.new(errors:)
        else
          message = 'Unknown EVSS Async Error'
          raise ::Common::Exceptions::UnprocessableEntity.new(detail: message)
        end
      end

      def format_evss_errors(errors)
        errors.map do |err|
          error = err.deep_symbolize_keys
          # Some old saved error messages saved key is an integer, so need to call .to_s before .gsub
          formatted = error[:key] ? error[:key].to_s.gsub('.', '/') : error[:key]
          { status: 422, detail: "#{error[:severity]} #{error[:detail] || error[:text]}".squish, source: formatted }
        end
      end

      # validate participant access using the participant id identity used to initialize this service
      def validate_bgs_participant!(bgs_claim)
        clm_prtcpnt_vet_id = nil
        clm_prtcpnt_clmnt_id = nil

        if bgs_claim&.dig(:benefit_claim_details_dto).present?
          clm_prtcpnt_vet_id = bgs_claim&.dig(:benefit_claim_details_dto, :ptcpnt_vet_id)&.to_s
          clm_prtcpnt_clmnt_id = bgs_claim&.dig(:benefit_claim_details_dto, :ptcpnt_clmant_id)&.to_s
        end

        if clm_prtcpnt_cannot_access_claim?(clm_prtcpnt_vet_id, clm_prtcpnt_clmnt_id)
          raise ::Common::Exceptions::ResourceNotFound.new(
            detail: INVALID_CLAIM_ACCESS_DETAIL
          )
        end
      end

      # validate the claim participant ids against the service identity's participant id to ensure access is valid
      def clm_prtcpnt_cannot_access_claim?(clm_prtcpnt_vet_id, clm_prtcpnt_clmnt_id)
        return true if clm_prtcpnt_vet_id.nil? || clm_prtcpnt_clmnt_id.nil?

        participant_id = target_veteran.participant_id&.to_s
        # if either of these is false then we have a match and can show the record
        clm_prtcpnt_vet_id != participant_id && clm_prtcpnt_clmnt_id != participant_id
      end
    end
  end
end
