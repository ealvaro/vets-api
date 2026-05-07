# frozen_string_literal: true

module AccreditedRepresentativePortal
  class SetOrgsAcceptanceModes2122Service
    extend Poa2122ServiceHelpers

    def self.call(poa_codes:, primary_mode:, default_rep_mode:)
      codes = normalize_codes(poa_codes)
      raise ArgumentError, 'POA codes required' if codes.empty?

      valid_modes = Veteran::Service::Organization::ACCEPTANCE_MODES
      raise ArgumentError, "Invalid primary_mode: #{primary_mode}" unless valid_modes.include?(primary_mode)
      raise ArgumentError, "Invalid default_rep_mode: #{default_rep_mode}" unless valid_modes.include?(default_rep_mode)

      orgs = organizations_for(codes)

      ActiveRecord::Base.transaction do
        {
          org_modes_updated: set_org_acceptance_modes!(orgs, primary_mode:, default_rep_mode:)
        }
      end
    end
  end
end
