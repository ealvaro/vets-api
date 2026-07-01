# frozen_string_literal: true

module AccreditedRepresentativePortal
  class PowerOfAttorneyRequestPolicy < ApplicationPolicy
    # The legacy and AccreditedX acceptance_mode enums share identical values
    # (any_request / self_only / no_acceptance), so sourcing from Accreditation is valid
    # for both flag states and removes the legacy-model coupling here.
    VALID_ACCEPTANCE_MODES = Accreditation.acceptance_modes.values.freeze

    def index?
      legacy_authorize
    end

    def show?
      authorize_with_individual_accept
    end

    def create_decision?
      authorize_with_individual_accept
    end

    def can_accept?
      authorize_with_individual_accept
    end

    private

    def legacy_authorize
      @user.power_of_attorney_holders.any?(&:accepts_digital_power_of_attorney_requests?)
    end

    def record_org_participates?
      poa_code = @record.power_of_attorney_holder_poa_code
      @user.power_of_attorney_holders.any? do |holder|
        holder.poa_code == poa_code && holder.accepts_digital_power_of_attorney_requests?
      end
    end

    def authorize_with_individual_accept
      return legacy_authorize unless @record.respond_to?(:power_of_attorney_holder_poa_code)

      return false unless record_org_participates?

      mode = acceptance_mode_for_record_org
      return false if mode.blank?
      return false unless VALID_ACCEPTANCE_MODES.include?(mode)

      return false if mode == 'no_acceptance'
      return true if mode == 'any_request'

      self_only_allows?
    end

    def acceptance_mode_for_record_org
      poa_code = @record.power_of_attorney_holder_poa_code
      holder = @user.power_of_attorney_holders.find { |h| h.poa_code == poa_code }
      holder&.acceptance_mode
    end

    def self_only_allows?
      request_reg_num = @record.accredited_individual_registration_number
      return false if request_reg_num.blank?

      Array(@user.registration_numbers).include?(request_reg_num)
    rescue => e
      Rails.logger.error("PowerOfAttorneyRequestPolicy#self_only_allows? failed: #{e.message}")
      false
    end

    class Scope < ApplicationPolicy::Scope
      def resolve
        base_scope
      end

      private

      def base_scope
        @scope.unredacted.for_power_of_attorney_holders(
          @user.power_of_attorney_holders.select(
            &:accepts_digital_power_of_attorney_requests?
          )
        )
      end
    end
  end
end
