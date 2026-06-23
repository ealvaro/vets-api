# frozen_string_literal: true

require 'evss/error_middleware'
require 'claims_api/evss_bgs_mapper'

module ClaimsApi
  module V1
    class ClaimsController < ApplicationController
      INVALID_CLAIM_ACCESS_DETAIL = 'Invalid claim ID for the veteran identified.'

      include ClaimsApi::PoaVerification
      include ClaimsApi::ClaimsRequests::ClaimValidation

      before_action { permit_scopes %w[claim.read] }
      before_action :verify_power_of_attorney!, if: :header_request?

      def index
        claims = claims_status_service.all(target_veteran.participant_id)
        claims_v1_logging('claims_v1_index', message: 'Claims not found') if claims == []
        raise ::Common::Exceptions::ResourceNotFound.new(detail: 'Claims not found') if claims == []

        render json: ClaimsApi::ClaimListSerializer.new(claims)
      rescue EVSS::ErrorMiddleware::EVSSError => e
        claims_v1_logging('claims_index', message: e.message)
        raise ::Common::Exceptions::ResourceNotFound.new(detail: 'Claims not found')
      end

      def show
        # find the claim and validate against BGS before returning
        claim = find_lighthouse_claim!(claim_id: params[:id])
        validate_access_against_bgs(claim)

        if claim && claim.status == 'errored'
          fetch_errored(claim)
        elsif claim && claim.evss_id.blank?
          render json: ClaimsApi::AutoEstablishedClaimSerializer.new(claim)
        elsif claim && claim.evss_id.present?
          updated_claim = claims_status_service.update_from_remote(claim.evss_id)
          render json: ClaimsApi::ClaimDetailSerializer.new(updated_claim, { params: { uuid: claim.id } })
        elsif /^\d{2,20}$/.match?(params[:id])
          claim = claims_status_service.update_from_remote(params[:id])
          # NOTE: source doesn't seem to be accessible within a remote evss_claim
          render json: ClaimsApi::ClaimDetailSerializer.new(claim)
        else
          raise_claim_not_found!
        end
      rescue => e
        show_error_response(e)
      end

      private

      def show_error_response(error)
        if invalid_claim_access_error?(error)
          claims_v1_logging('claims_show', message: error.message)
          raise error
        end

        unless error.is_a?(::Common::Exceptions::ResourceNotFound)
          claims_v1_logging('claims_show', message: error.message)
          raise if error.is_a?(::Common::Exceptions::UnprocessableEntity)
        end

        raise_claim_not_found!
      end

      def invalid_claim_access_error?(error)
        error.is_a?(::Common::Exceptions::ResourceNotFound) &&
          error.errors[0]&.detail == INVALID_CLAIM_ACCESS_DETAIL
      end

      def raise_claim_not_found!
        claims_v1_logging('claims_show', message: 'Claim not found')
        raise ::Common::Exceptions::ResourceNotFound.new(detail: 'Claim not found')
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

      def validate_access_against_bgs(claim)
        # use evss_id unless claim could not be found
        benefit_claim_id = claim&.evss_id || params[:id]
        bgs_claim = find_bgs_claim!(claim_id: benefit_claim_id)

        raise ::Common::Exceptions::ResourceNotFound.new(detail: 'Claim not found') if claim.blank? && bgs_claim.blank?

        validate_id_with_icn(bgs_claim, claim, target_veteran&.mpi&.icn)
      end

      def find_lighthouse_claim!(claim_id:)
        lighthouse_claim = ClaimsApi::AutoEstablishedClaim.get_by_id_and_icn(
          claim_id, target_veteran&.mpi&.icn
        )

        if looking_for_lighthouse_claim?(claim_id:) && lighthouse_claim.blank?
          raise ::Common::Exceptions::ResourceNotFound.new(detail: 'Claim not found')
        end

        lighthouse_claim
      end

      def looking_for_lighthouse_claim?(claim_id:)
        claim_id.to_s.include?('-')
      end

      def find_bgs_claim!(claim_id:)
        return if claim_id.blank?

        claims_status_service&.find_benefit_claim_details_by_benefit_claim_id(
          claim_id
        )
      end
    end
  end
end
