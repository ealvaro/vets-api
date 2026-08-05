# frozen_string_literal: true

module AccreditedRepresentativePortal
  module V0
    class ClaimantController < ApplicationController
      BENEFIT_TYPES = %w[compensation pension survivor].freeze

      SHOW_ATTEMPT_METRIC = 'ar.claimant.show.attempt'
      SHOW_SUCCESS_METRIC = 'ar.claimant.show.success'
      SHOW_ERROR_METRIC   = 'ar.claimant.show.error'

      SEARCH_ATTEMPT_METRIC = 'ar.claimant.search.attempt'
      SEARCH_SUCCESS_METRIC = 'ar.claimant.search.success'
      SEARCH_NO_CLAIMANT_FOUND_METRIC = 'ar.claimant.search.no_claimant_found'
      SEARCH_ERROR_METRIC = 'ar.claimant.search.error'

      before_action :validate_benefit_type!, only: :show
      before_action { authorize nil, policy_class: ClaimantPolicy }

      def search # rubocop:disable Metrics/MethodLength
        monitoring = ar_monitoring
        monitoring.track_count(SEARCH_ATTEMPT_METRIC, tags: default_tags)

        claimant_profile =
          MPI::Service.new.find_profile_by_attributes(
            first_name: params[:first_name],
            last_name: params[:last_name],
            ssn: params[:ssn].try(:gsub, /\D/, ''),
            birth_date: params[:dob]
          ).profile

        if claimant_profile.blank?
          monitoring.track_count(SEARCH_NO_CLAIMANT_FOUND_METRIC, tags: default_tags)
          return render json: { data: nil }
        end

        @icn = claimant_profile.icn

        power_of_attorney_requests = claimant_poa_requests(claimant_profile.icn)

        # A claimant is only revealed when the rep has established POA or there is a
        # still-pending request. Resolved requests (declined/expired/accepted-elsewhere)
        # do not grant continued visibility into the claimant.
        unless claimant_representative.present? || power_of_attorney_requests.unresolved.exists?
          monitoring.track_count(SEARCH_NO_CLAIMANT_FOUND_METRIC, tags: default_tags)
          return render json: { data: nil }
        end

        serializer =
          ClaimantSerializer.new(
            power_of_attorney_requests:,
            claimant_representative:,
            claimant_profile:,
            current_user:
          )

        data = serializer.serializable_hash
        monitoring.track_count(SEARCH_SUCCESS_METRIC, tags: default_tags)

        render json: { data: }
      rescue MPI::Errors::ArgumentError => e
        normalized_reason = e.class.name.split('::').last
        monitoring.track_count(SEARCH_ERROR_METRIC, tags: default_tags + ["reason:#{normalized_reason}"])

        raise Common::Exceptions::BadRequest.new(
          detail: e.message
        )
      end

      def show
        monitoring = ar_monitoring
        monitoring.track_count(SHOW_ATTEMPT_METRIC, tags: default_tags)

        @icn = IcnTemporaryIdentifier.lookup_icn(params[:id])
        claimant_representative.present? or raise Pundit::NotAuthorizedError

        render json: claimant_details_payload(claimant_details_poa_requests)
        monitoring.track_count(SHOW_SUCCESS_METRIC, tags: default_tags)
      rescue ActiveRecord::RecordNotFound
        monitoring.track_count(SHOW_ERROR_METRIC, tags: default_tags + ['reason:RecordNotFound'])
        raise Common::Exceptions::RecordNotFound, 'Claimant not found'
      rescue => e
        normalized_reason = e.class.name.split('::').last
        monitoring.track_count(SHOW_ERROR_METRIC, tags: default_tags + ["reason:#{normalized_reason}"])
        raise
      end

      private

      def claimant_details_payload(power_of_attorney_requests)
        service_args = {
          icn: @icn,
          representative_name: claimant_representative.power_of_attorney_holder.name,
          benefit_type_param: params[:benefitType]
        }

        if pending_notice_enabled?
          service_args[:power_of_attorney_requests] = power_of_attorney_requests
          service_args[:is_representative] = claimant_representative.present?
        end

        AccreditedRepresentativePortal::ClaimantDetailsService.new(**service_args).call
      end

      def claimant_details_poa_requests
        return [] unless pending_notice_enabled?

        claimant_poa_requests(@icn)
      end

      def pending_notice_enabled?
        Flipper.enabled?(:accredited_representative_portal_cd_pending_notice)
      end

      def claimant_poa_requests(icn)
        policy_scope(PowerOfAttorneyRequest)
          .joins(:claimant)
          .includes(:resolution, resolution: :resolving)
          .not_withdrawn
          .where(claimant: { icn: })
      end

      def validate_benefit_type!
        benefit_type = params[:benefitType]
        return if benefit_type.blank?
        return if BENEFIT_TYPES.include?(benefit_type)

        raise Common::Exceptions::UnprocessableEntity.new(
          detail: "benefitType must be one of: #{BENEFIT_TYPES.join(', ')}"
        )
      end

      def claimant_representative
        @claimant_representative ||= ClaimantRepresentative.find(
          claimant_icn: @icn,
          power_of_attorney_holder_memberships:
            current_user.power_of_attorney_holder_memberships
        )
      rescue ActiveRecord::RecordNotFound, ClaimantRepresentative::Finder::Error
        nil
      end

      def power_of_attorney_holder
        claimant_representative.power_of_attorney_holder
      end

      def ar_monitoring
        AccreditedRepresentativePortal::Monitoring.new(
          AccreditedRepresentativePortal::Monitoring::NAME,
          default_tags:
        )
      end

      # ---- Defensive Datadog tags only ----
      def default_tags
        org_tag = 'org_resolve:failed'
        poa_code = organization
        org_tag = "org:#{poa_code}" if poa_code.present?

        [org_tag]
      end

      # nil-safe retrieval for monitoring only
      def organization
        power_of_attorney_holder&.poa_code
      rescue
        nil
      end
    end
  end
end
