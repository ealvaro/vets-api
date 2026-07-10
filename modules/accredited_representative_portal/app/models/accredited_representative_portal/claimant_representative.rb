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
        holder = membership.power_of_attorney_holder

        # Explicit allow-list: fail closed for any unexpected/blank holder type rather than defaulting
        # to allowed.
        case holder.type
        when PowerOfAttorneyHolder::Types::ATTORNEY, PowerOfAttorneyHolder::Types::CLAIMS_AGENT
          # Attorneys and claims agents hold POA as individuals — they have no organization and
          # therefore no OrganizationRepresentative/Accreditation record. Reaching here means the
          # claimant's established POA code (from the Benefits Claims API, which reflects only
          # established POAs) already matches this membership, which is sufficient for them to VIEW
          # the claimant.
          true
        when PowerOfAttorneyHolder::Types::VETERAN_SERVICE_ORGANIZATION
          # Once a POA is accepted it belongs to the whole org, so any rep with an active accreditation
          # in it may VIEW the claimant, regardless of acceptance_mode. acceptance_mode (including
          # no_acceptance) and the self_only "named in 16A" rule only govern ACTING on a pending
          # request, which is enforced separately by PowerOfAttorneyRequestPolicy#can_accept?.
          active_accreditation?(holder, membership.registration_number)
        else
          false
        end
      end

      def active_accreditation?(holder, registration_number)
        if AccreditedRepresentativePortal.use_accredited_models?
          Accreditation
            .active
            .for_organization_poa_codes(holder.poa_code)
            .for_registration_numbers(registration_number)
            .exists?
        else
          Veteran::Service::OrganizationRepresentative.active.exists?(
            organization_poa: holder.poa_code,
            representative_id: registration_number
          )
        end
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
