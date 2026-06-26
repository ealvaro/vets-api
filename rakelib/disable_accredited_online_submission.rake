# frozen_string_literal: true

namespace :vso do
  desc 'Disable accredited online submission of VA Form 21-22 for the given POA code(s)'
  #
  # Usage:
  #   bundle exec rake "vso:disable_accredited_online_submission[083]"
  #   bundle exec rake "vso:disable_accredited_online_submission[083,074,095]"
  #
  # Sets can_accept_digital_poa_requests=false, all reps to no_acceptance,
  # and both org-level acceptance mode columns to no_acceptance.
  #
  task :disable_accredited_online_submission, [:poa_codes] => :environment do |_t, args|
    raise ArgumentError, 'POA codes required' if args[:poa_codes].blank?

    poa_codes = [args[:poa_codes], *args.extras].compact.uniq

    Rails.logger.tagged('rake:vso:disable_accredited_online_submission') do
      Rails.logger.info("Received POA codes: #{poa_codes.join(', ')}")
      Rails.logger.info('Disabling accredited online submission for matching organization(s)...')

      result = AccreditedRepresentativePortal::DisableAccreditedOnlineSubmission2122Service.call(poa_codes:)

      Rails.logger.info("Disabled accredited online submission for #{result[:orgs_updated]} organization(s).")
      Rails.logger.info(
        "Set acceptance_mode=no_acceptance for #{result[:reps_updated]} active accreditation(s)."
      )
      Rails.logger.info("Set org acceptance modes to no_acceptance for #{result[:org_modes_updated]} org(s).")
    end
  end
end
