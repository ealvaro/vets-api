# frozen_string_literal: true

module AccreditedRepresentativePortal
  class ConfigureOnlineSubmission2122Service
    extend Poa2122ServiceHelpers

    def self.call(poa_codes:, acceptance_mode:, default_new_rep_mode:)
      codes = normalize_codes(poa_codes)
      raise ArgumentError, 'POA codes required' if codes.empty?

      validate_mode!(acceptance_mode, 'acceptance_mode')
      validate_mode!(default_new_rep_mode, 'default_new_rep_mode')

      orgs = organizations_for(codes)

      ActiveRecord::Base.transaction do
        {
          orgs_updated: enable_online_submission!(orgs),
          reps_updated: set_active_reps_mode!(orgs, acceptance_mode),
          org_modes_updated: set_org_acceptance_modes!(
            orgs,
            primary_mode: acceptance_mode,
            default_rep_mode: default_new_rep_mode
          )
        }
      end
    end

    def self.enable_online_submission!(org_scope)
      orgs_to_update = org_scope.where.not(can_accept_digital_poa_requests: true)

      expected = orgs_to_update.count
      updated = orgs_to_update.update_all(can_accept_digital_poa_requests: true) # rubocop:disable Rails/SkipsModelValidations

      if updated != expected
        raise MismatchError,
              "ConfigureOnlineSubmission2122Service mismatch: expected #{expected} orgs, updated #{updated}"
      end

      updated
    end
    private_class_method :enable_online_submission!

    def self.validate_mode!(mode, label)
      valid_modes = Veteran::Service::Organization::ACCEPTANCE_MODES
      raise ArgumentError, "Invalid #{label}: #{mode}" unless valid_modes.include?(mode)
    end
    private_class_method :validate_mode!
  end
end
