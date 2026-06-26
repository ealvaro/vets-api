# frozen_string_literal: true

namespace :vso do
  desc <<~DESC
    Set accredited org-level acceptance mode columns WITHOUT touching existing reps.

    Use this when an org has mixed rep modes (e.g., some self_only, some no_acceptance)
    and you want to change the org's default_new_rep_acceptance_mode (used by the Trexler
    sync for newly added reps) or primary_org_acceptance_mode, without overwriting each
    rep's current mode.

    If you want to set all reps AND org columns at once, use configure_accredited_online_submission instead.
  DESC
  #
  # Usage:
  #   bundle exec rake "vso:set_accredited_orgs_acceptance_modes[083,self_only,no_acceptance]"
  #   bundle exec rake "vso:set_accredited_orgs_acceptance_modes[083 074 016,self_only,no_acceptance]"
  #
  # Note: Multiple POA codes must be space-separated (commas are rake arg delimiters).
  #       Internally, both comma and space-separated formats are supported.
  #
  # Args:
  #   poa_codes          - Space-separated or comma-separated POA codes
  #   primary_mode       - The org's primary acceptance mode (any_request, self_only, no_acceptance)
  #   default_rep_mode   - Mode assigned to new reps added via Trexler sync
  #
  task :set_accredited_orgs_acceptance_modes, %i[poa_codes primary_mode default_rep_mode] => :environment do |_t, args|
    raise ArgumentError, 'POA codes required' if args[:poa_codes].blank?
    raise ArgumentError, 'primary_mode required (any_request, self_only, no_acceptance)' if args[:primary_mode].blank?
    if args[:default_rep_mode].blank?
      raise ArgumentError, 'default_rep_mode required (any_request, self_only, no_acceptance)'
    end

    poa_codes = args[:poa_codes].strip
    primary_mode = args[:primary_mode].strip
    default_rep_mode = args[:default_rep_mode].strip

    Rails.logger.tagged('rake:vso:set_accredited_orgs_acceptance_modes') do
      Rails.logger.info("POA codes: #{poa_codes}, primary_mode: #{primary_mode}, default_rep_mode: #{default_rep_mode}")
      Rails.logger.info('Setting accredited org-level acceptance mode columns (reps will NOT be changed)...')

      result = AccreditedRepresentativePortal::SetAccreditedOrgsAcceptanceModes2122Service.call(
        poa_codes:, primary_mode:, default_rep_mode:
      )

      Rails.logger.info("Updated accredited org acceptance modes for #{result[:org_modes_updated]} org(s).")
    end
  end
end
