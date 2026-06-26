# frozen_string_literal: true

namespace :vso do
  desc 'Enable or change accredited online submission of VA Form 21-22 for the given POA code(s)'
  #
  # Usage:
  #   bundle exec rake "vso:configure_accredited_online_submission[083,any_request,any_request]"
  #   bundle exec rake "vso:configure_accredited_online_submission[083,self_only,no_acceptance]"
  #   bundle exec rake "vso:configure_accredited_online_submission[083 074 016,any_request,any_request]"
  #
  # Note: Multiple POA codes must be space-separated (commas are rake arg delimiters).
  #       Internally, both comma and space-separated formats are supported.
  #
  # Args:
  #   poa_codes          - Space-separated or comma-separated POA codes
  #   acceptance_mode    - Mode for existing reps (any_request, self_only, no_acceptance)
  #   default_rep_mode   - Mode for new reps added via Trexler sync
  #
  task :configure_accredited_online_submission,
       %i[poa_codes acceptance_mode default_rep_mode] => :environment do |_t, args|
    raise ArgumentError, 'POA codes required' if args[:poa_codes].blank?
    if args[:acceptance_mode].blank?
      raise ArgumentError, 'acceptance_mode required (any_request, self_only, no_acceptance)'
    end
    if args[:default_rep_mode].blank?
      raise ArgumentError, 'default_rep_mode required (any_request, self_only, no_acceptance)'
    end

    poa_codes = args[:poa_codes].strip
    acceptance_mode = args[:acceptance_mode].strip
    default_rep_mode = args[:default_rep_mode].strip

    Rails.logger.tagged('rake:vso:configure_accredited_online_submission') do
      Rails.logger.info(
        "POA codes: #{poa_codes}, acceptance_mode: #{acceptance_mode}, default_rep_mode: #{default_rep_mode}"
      )
      Rails.logger.info('Configuring accredited online submission for matching organization(s)...')

      result = AccreditedRepresentativePortal::ConfigureAccreditedOnlineSubmission2122Service.call(
        poa_codes:, acceptance_mode:, default_new_rep_mode: default_rep_mode
      )

      Rails.logger.info("Enabled accredited online submission for #{result[:orgs_updated]} organization(s).")
      Rails.logger.info(
        "Set acceptance_mode=#{acceptance_mode} for #{result[:reps_updated]} active accreditation(s)."
      )
      Rails.logger.info(
        "Set org acceptance modes (primary=#{acceptance_mode}, default_new_rep=#{default_rep_mode})" \
        " for #{result[:org_modes_updated]} org(s)."
      )
    end
  end
end
