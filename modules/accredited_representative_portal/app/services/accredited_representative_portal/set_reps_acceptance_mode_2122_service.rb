# frozen_string_literal: true

module AccreditedRepresentativePortal
  class SetRepsAcceptanceMode2122Service
    extend Poa2122ServiceHelpers

    def self.call(poa_code:, rep_ids:, mode:)
      poa_code = poa_code.to_s.strip
      rep_ids = Array(rep_ids).filter_map { |id| id.to_s.strip.presence }.uniq

      raise ArgumentError, 'POA code required' if poa_code.blank?
      raise ArgumentError, 'Representative IDs required' if rep_ids.empty?
      unless Veteran::Service::Organization::ACCEPTANCE_MODES.include?(mode)
        raise ArgumentError, "Invalid mode: #{mode}"
      end

      Veteran::Service::Organization.find_by!(poa: poa_code)

      ActiveRecord::Base.transaction do
        {
          reps_updated: set_specific_reps_mode!(poa_code, rep_ids, mode)
        }
      end
    end
  end
end
