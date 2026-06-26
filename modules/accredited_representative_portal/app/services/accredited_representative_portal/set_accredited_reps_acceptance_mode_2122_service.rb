# frozen_string_literal: true

module AccreditedRepresentativePortal
  class SetAccreditedRepsAcceptanceMode2122Service
    extend AccreditedRepresentativePortal::AccreditedPoa2122ServiceHelpers

    def self.call(poa_code:, rep_ids:, mode:)
      poa_code = poa_code.to_s.strip
      registration_numbers = Array(rep_ids).filter_map { |id| id.to_s.strip.presence }.uniq

      raise ArgumentError, 'POA code required' if poa_code.blank?
      raise ArgumentError, 'Representative IDs required' if registration_numbers.empty?

      validate_mode!(mode, 'mode')

      AccreditedOrganization.find_by!(poa_code:)

      ActiveRecord::Base.transaction do
        {
          reps_updated: set_specific_reps_mode!(poa_code, registration_numbers, mode)
        }
      end
    end
  end
end
