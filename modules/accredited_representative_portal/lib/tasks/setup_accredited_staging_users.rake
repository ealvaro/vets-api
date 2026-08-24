# frozen_string_literal: true

require 'base64'
require 'csv'
require 'github/installation_token_generator'

module AccreditedRepresentativePortal
  module SetupAccreditedStagingUsers
    USER_TYPE_MAP = {
      'attorney' => 'attorney',
      'claim_agent' => 'claims_agent',
      'claim_agents' => 'claims_agent',
      'claims_agent' => 'claims_agent',
      'representative' => 'representative',
      'veteran_service_officer' => 'representative',
      'vso' => 'representative'
    }.freeze

    module_function

    def individual_type_for(user_type)
      USER_TYPE_MAP[user_type.to_s.strip.downcase]
    end

    def poa_codes_for(attributes)
      attributes
        .values_at('poa_code_1', 'poa_code_2')
        .map { |poa_code| poa_code.to_s.strip }
        .compact_blank
        .uniq
    end

    def apply_poa_code!(individual, individual_type, poa_codes)
      individual.poa_code =
        if individual_type == AccreditedIndividual::INDIVIDUAL_TYPE_VSO_REPRESENTATIVE
          nil
        else
          poa_codes.first
        end
    end

    # rubocop:disable Metrics/MethodLength
    def sync_representative_accreditations!(individual, poa_codes, result)
      return unless individual.individual_type == AccreditedIndividual::INDIVIDUAL_TYPE_VSO_REPRESENTATIVE

      poa_codes.each_with_index do |poa_code, index|
        organization = AccreditedOrganization.find_by(poa_code:)

        unless organization
          result[:missing_org_count] += 1
          Rails.logger.info(
            "Could not find AccreditedOrganization #{poa_code} " \
            "for AccreditedIndividual #{individual.registration_number}"
          )
          next
        end

        accreditation = Accreditation.find_or_initialize_by(
          accredited_individual: individual,
          accredited_organization: organization
        )
        # Alternate acceptance mode so individual-accept can be exercised across both modes.
        accreditation.acceptance_mode = index.even? ? 'any_request' : 'self_only'

        if accreditation.new_record?
          accreditation.save!
          result[:accreditations_created_count] += 1
        elsif accreditation.deactivated_at.present?
          accreditation.activate!
          result[:accreditations_activated_count] += 1
        elsif accreditation.changed?
          accreditation.save!
        end
      end
    end
    # rubocop:enable Metrics/MethodLength
  end
end

namespace :accredited_representative_portal do
  desc <<~MSG.squish
    Seeds accredited representative records for staging using Accredited* tables
  MSG
  task setup_accredited_staging_users: :environment do
    unless ENV['APPLICATION_ENV'] == 'staging'
      Rails.logger.warn(<<~MSG.squish)
        Whoops! This task can only be run in the staging environment.
        Stopping now.
      MSG

      exit!(1)
    end

    config = Settings.accredited_representative_portal.allow_list.github

    api_endpoint = config.base_uri.to_s
    app_id = config.app_id.to_s
    private_key = config.private_key.to_s
    org = config.org.to_s
    repo = config.repo.to_s
    path = config.path.to_s

    raise ArgumentError, 'GitHub allow_list config missing base_uri' if api_endpoint.blank?
    raise ArgumentError, 'GitHub allow_list config missing app_id' if app_id.blank?
    raise ArgumentError, 'GitHub allow_list config missing private_key' if private_key.blank?
    raise ArgumentError, 'GitHub allow_list config missing org' if org.blank?
    raise ArgumentError, 'GitHub allow_list config missing repo' if repo.blank?
    raise ArgumentError, 'GitHub allow_list config missing path' if path.blank?

    access_token = Github::InstallationTokenGenerator
                   .new(app_id:, private_key:, api_endpoint:)
                   .generate(org:)

    client = Octokit::Client.new(api_endpoint:, access_token:)

    csv = client
          .contents(repo, path:)
          .then { |contents| Base64.decode64(contents[:content]) }
          .then { |content| CSV.parse(content, headers: true) }

    records = csv.map(&:to_h)

    results = {
      not_found_count: 0,
      updated_count: 0,
      error_count: 0,
      missing_org_count: 0,
      accreditations_created_count: 0,
      accreditations_activated_count: 0
    }

    records.each do |attributes|
      registration_number = attributes['representative_id'].to_s.strip
      individual = AccreditedIndividual.find_by(registration_number:)

      unless individual
        results[:not_found_count] += 1
        Rails.logger.info("Could not find AccreditedIndividual #{registration_number}")
        next
      end

      begin
        individual_type =
          AccreditedRepresentativePortal::SetupAccreditedStagingUsers.individual_type_for(
            attributes['user_type']
          )

        raise ArgumentError, "Unsupported user_type: #{attributes['user_type']}" unless individual_type

        poa_codes = AccreditedRepresentativePortal::SetupAccreditedStagingUsers.poa_codes_for(attributes)

        individual.individual_type = individual_type
        individual.email = attributes['email'].to_s.strip.presence

        AccreditedRepresentativePortal::SetupAccreditedStagingUsers.apply_poa_code!(
          individual,
          individual_type,
          poa_codes
        )

        individual.save!

        AccreditedRepresentativePortal::SetupAccreditedStagingUsers.sync_representative_accreditations!(
          individual,
          poa_codes,
          results
        )

        results[:updated_count] += 1
      rescue => e
        results[:error_count] += 1
        Rails.logger.info(e)
      end
    end

    Rails.logger.info('Updated ARP staging accredited individuals:')
    Rails.logger.info(results)
  end
end
