# frozen_string_literal: true

namespace :vso do
  desc 'Set accredited acceptance_mode for specific reps within an organization'
  #
  # Usage:
  #   bundle exec rake "vso:set_accredited_reps_acceptance_mode[083,self_only,12345,67890]"
  #
  # Args:
  #   poa_code     - The organization's POA code
  #   mode         - The acceptance mode (any_request, self_only, no_acceptance)
  #   rep_ids...   - One or more representative registration numbers
  #
  task :set_accredited_reps_acceptance_mode, %i[poa_code mode] => :environment do |_t, args|
    raise ArgumentError, 'POA code required' if args[:poa_code].blank?
    raise ArgumentError, 'Mode required (any_request, self_only, no_acceptance)' if args[:mode].blank?

    poa_code = args[:poa_code].strip
    mode = args[:mode].strip
    rep_ids = args.extras.map(&:strip).compact_blank.uniq

    raise ArgumentError, 'At least one representative ID required' if rep_ids.empty?

    Rails.logger.tagged('rake:vso:set_accredited_reps_acceptance_mode') do
      Rails.logger.info("POA code: #{poa_code}, mode: #{mode}, rep IDs: #{rep_ids.join(', ')}")

      result = AccreditedRepresentativePortal::SetAccreditedRepsAcceptanceMode2122Service.call(
        poa_code:, rep_ids:, mode:
      )

      Rails.logger.info("Set accredited acceptance_mode=#{mode} for #{result[:reps_updated]} active accreditation(s).")
    end
  end
end
