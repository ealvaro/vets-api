# frozen_string_literal: true

module V0
  class EVSSClaimsController < ApplicationController
    include IgnoreNotFound
    include InboundRequestLogging
    include V0::Concerns::EVSSDeprecation
    service_tag 'claim-status'

    before_action { authorize :evss, :access? }
    before_action :log_request_origin

    def index
      claims, synchronized = service.all

      options = { meta: { successful_sync: synchronized } }
      render json: EVSSClaimListSerializer.new(claims, options)
    end

    def show
      claim = EVSSClaim.for_user(current_user).find_by(evss_id: params[:id])
      raise Common::Exceptions::RecordNotFound, params[:id] unless claim

      claim, synchronized = service.update_from_remote(claim)
      options = { meta: { successful_sync: synchronized } }
      render json: EVSSClaimDetailSerializer.new(claim, options)
    end

    def request_decision
      claim = EVSSClaim.for_user(current_user).find_by(evss_id: params[:id])
      raise Common::Exceptions::RecordNotFound, params[:id] unless claim

      jid = service.request_decision(claim)
      claim.update(requested_decision: true)
      render_job_id(jid)
    end

    private

    def log_request_origin
      return unless Flipper.enabled?(:log_claims_request_origin)

      log_inbound_request(message_type: 'evss.cst.inbound_request', message: 'Inbound request (EVSS claim status)')
    end

    def skip_reportable_types
      super + [Common::Exceptions::BackendServiceException]
    end

    def service
      EVSSClaimService.new(current_user)
    end
  end
end
