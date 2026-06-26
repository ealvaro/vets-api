# frozen_string_literal: true

module AccreditedRepresentativePortal
  class SetAccreditedOrgsAcceptanceModes2122Service
    extend AccreditedRepresentativePortal::AccreditedPoa2122ServiceHelpers

    def self.call(poa_codes:, primary_mode:, default_rep_mode:)
      codes = normalize_codes(poa_codes)
      raise ArgumentError, 'POA codes required' if codes.empty?

      validate_mode!(primary_mode, 'primary_mode')
      validate_mode!(default_rep_mode, 'default_rep_mode')

      orgs = organizations_for(codes)

      ActiveRecord::Base.transaction do
        {
          org_modes_updated: set_org_acceptance_modes!(orgs, primary_mode:, default_rep_mode:)
        }
      end
    end
  end
end
