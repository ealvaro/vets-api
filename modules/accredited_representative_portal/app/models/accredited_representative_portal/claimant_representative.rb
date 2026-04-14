# frozen_string_literal: true

module AccreditedRepresentativePortal
  class ClaimantRepresentative <
    Data.define(
      :claimant_id,
      :accredited_individual_registration_number,
      :power_of_attorney_holder
    )
    class << self
      def find(...)
        Finder.new(...).perform
      end
    end

    class Finder
      Error = Class.new(RuntimeError)

      def initialize(claimant_icn:, power_of_attorney_holder_memberships:)
        @claimant =
          Claimant.new(icn: claimant_icn)

        @power_of_attorney_holder_memberships =
          power_of_attorney_holder_memberships
      end

      def perform
        @claimant.poa_code.present? or
          return nil

        membership =
          @power_of_attorney_holder_memberships.find(
            @claimant.poa_code
          )

        membership.present? or
          return nil

        return nil unless allowed_for_claimant?(membership)

        ClaimantRepresentative.new(
          claimant_id: @claimant.id,
          accredited_individual_registration_number:
            membership.registration_number,
          power_of_attorney_holder:
            membership.power_of_attorney_holder
        )
      rescue => e
        raise Error, e.message, e.backtrace
      end

      private

      def allowed_for_claimant?(membership)
        return true unless individual_accept_enabled?

        org_rep_membership = Veteran::Service::OrganizationRepresentative.active.find_by(
          organization_poa: membership.power_of_attorney_holder.poa_code,
          representative_id: membership.registration_number
        )

        return false if org_rep_membership.blank?
        return false if org_rep_membership.no_acceptance?
        return true if org_rep_membership.any_request?

        allowed_self_only_for_claimant?(membership)
      end

      def allowed_self_only_for_claimant?(membership)
        PowerOfAttorneyRequest
          .joins(:claimant)
          .not_withdrawn
          .exists?(claimant: { icn: @claimant.icn },
                   power_of_attorney_holder_poa_code: membership.power_of_attorney_holder.poa_code,
                   accredited_individual_registration_number: membership.registration_number)
      end

      def individual_accept_enabled?
        Flipper.enabled?(:accredited_representative_portal_individual_accept_backend)
      end
    end

    class Claimant
      attr_reader :icn

      def initialize(id: nil, icn: nil)
        unless [id, icn].one?(&:present?)
          raise ArgumentError, <<~MSG.squish
            exactly one of `id' or `icn'
            must be present
          MSG
        end

        @id = id
        @icn = icn
      end

      delegate :id, to: :identifier

      def poa_code
        defined?(@poa_code) and
          return @poa_code

        @poa_code =
          begin
            service = BenefitsClaims::Service.new(identifier.icn)
            response = service.get_power_of_attorney['data'].to_h
            response.dig('attributes', 'code')
          end
      end

      private

      def identifier
        @identifier ||=
          if @icn.present?
            IcnTemporaryIdentifier.find_or_create_by(icn: @icn)
          else
            IcnTemporaryIdentifier.find(@id)
          end
      end
    end
  end
end
