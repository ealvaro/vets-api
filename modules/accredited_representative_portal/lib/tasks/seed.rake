# frozen_string_literal: true

require_relative 'seed/records'

namespace :accredited_representative_portal do
  desc <<~MSG.squish
    Seeds accredited representative and POA request records
  MSG
  task seed: :environment do
    unless Rails.env.development?
      Rails.logger.warn(<<~MSG.squish)
        Whoops! This task can only be run in the development environment.
        Stopping now.
      MSG

      exit!(1)
    end

    AccreditedRepresentativePortal::Seed.run
  end
end

# rubocop:disable Metrics/MethodLength, Metrics/ModuleLength, Rails/SkipsModelValidations
module AccreditedRepresentativePortal
  ##
  # Representative records derived from here:
  # https://va.ghe.com/software/va.gov-team-sensitive/blob/master/products/accredited-representation-management/accredited-entities-test-data.md
  #
  module Seed
    class << self
      def run
        ActiveRecord::Base.transaction do
          insert_all(
            Records::ATTORNEYS,
            factory: %i[
              accredited_individual
              attorney
            ]
          )

          insert_all(
            Records::CLAIMS_AGENTS,
            factory: %i[
              accredited_individual
              claims_agent
            ]
          )

          accreditations = build_accreditations

          if AccreditedRepresentativePortal.use_accredited_models?
            insert_accredited_vso_records
          else
            insert_legacy_vso_records
          end

          insert_all(
            Records::CLAIMANTS,
            factory: [
              :user_account
            ]
          )

          insert_poa_requests(
            accreditations
          )
        end
      end

      private

      ##
      # The `accredited_individual_id` / `accredited_organization_id` values here are the
      # `registration_number` / `poa_code` strings that back the shared POA-request FK
      # columns, so they are identical regardless of which model layer is seeded.
      #
      def build_accreditations
        Records::REPRESENTATIVES.flat_map do |representative|
          representative[:poa_codes].map do |poa_code|
            {
              accredited_individual_id: representative[:representative_id],
              accredited_organization_id: poa_code
            }
          end
        end
      end

      def insert_legacy_vso_records
        insert_all(
          Records::ORGANIZATIONS,
          factory: [
            :organization
          ]
        )

        insert_all(
          Records::REPRESENTATIVES,
          factory: %i[representative],
          unique_by: %i[representative_id]
        )

        insert_all(
          Records::ORGANIZATION_REPRESENTATIVES,
          factory: [:organization_representative],
          unique_by: %i[organization_poa representative_id]
        )
      end

      def insert_accredited_vso_records
        insert_all(
          accredited_organization_records,
          factory: [:accredited_organization],
          unique_by: %i[poa_code]
        )

        insert_all(
          accredited_individual_records,
          factory: %i[accredited_individual representative],
          unique_by: %i[registration_number individual_type]
        )

        insert_accreditations
      end

      def accredited_organization_records
        Records::ORGANIZATIONS.map.with_index do |organization, index|
          {
            name: organization[:name],
            poa_code: organization[:poa],
            # Alternate digital acceptance so both digital and non-digital orgs are seeded.
            can_accept_digital_poa_requests: index.even?
          }
        end
      end

      def accredited_individual_records
        Records::REPRESENTATIVES.map do |representative|
          {
            first_name: representative[:first_name],
            last_name: representative[:last_name],
            registration_number: representative[:representative_id],
            email: representative[:email]
          }
        end
      end

      ##
      # Builds the `Accreditation` join rows linking the seeded representatives to their
      # organizations. Acceptance mode alternates by representative so individual-accept can
      # be exercised across both `any_request` and `self_only`.
      #
      def insert_accreditations
        organizations_by_poa_code =
          AccreditedOrganization
          .where(poa_code: Records::ORGANIZATIONS.map { |organization| organization[:poa] })
          .index_by(&:poa_code)

        individuals_by_registration_number =
          AccreditedIndividual
          .representatives
          .where(registration_number: Records::REPRESENTATIVES.map { |rep| rep[:representative_id] })
          .index_by(&:registration_number)

        rows =
          Records::REPRESENTATIVES.each_with_index.flat_map do |representative, index|
            individual = individuals_by_registration_number[representative[:representative_id]]
            next [] unless individual

            acceptance_mode = index.even? ? 'any_request' : 'self_only'

            representative[:poa_codes].filter_map do |poa_code|
              organization = organizations_by_poa_code[poa_code]
              next unless organization

              {
                accredited_individual_id: individual.id,
                accredited_organization_id: organization.id,
                acceptance_mode:,
                can_accept_reject_poa: true
              }
            end
          end

        return if rows.empty?

        Accreditation.insert_all(
          rows,
          unique_by: %i[accredited_individual_id accredited_organization_id]
        )
      end

      def find_accredited_individual(registration_number)
        if AccreditedRepresentativePortal.use_accredited_models?
          AccreditedIndividual.representatives.find_by(registration_number:)
        else
          Veteran::Service::Representative.find_by(representative_id: registration_number)
        end
      end

      ##
      # There is one claimant per accreditation. The claimant then gets a permutation
      # of having a series of one of each POA request resolution and applies it.
      # All this cycles around the accreditations. Finally, give each accredited
      # individual one pending POA request.
      #
      def insert_poa_requests(accreditations)
        poa_forms = []
        resolutions = []
        resolution_traits = []
        poa_requests = []

        accreditation_cycle = accreditations.cycle
        claimant_poa_forms = {}

        Records::CLAIMANTS.each do |claimant|
          claimant_id = claimant[:id]
          claimant_poa_forms[claimant_id] =
            FactoryBot.build(:power_of_attorney_form)

          RESOLUTION_HISTORY_CYCLE.next.each do |resolution_trait|
            accreditation = accreditation_cycle.next
            created_at = RESOLVED_TIME_TRAVELER.next

            accredited_representative =
              find_accredited_individual(accreditation[:accredited_individual_id])
            id = Records::POA_REQUEST_IDS.next
            unless AccreditedRepresentativePortal::PowerOfAttorneyRequest.exists?(id:)
              poa_forms.push(claimant_poa_forms[claimant_id].dup)
              resolutions.push(created_at: created_at + 1.day)
              resolution_traits.push(resolution_trait)
              poa_requests.push(
                id:,
                claimant_type: 'veteran',
                claimant_id:,
                power_of_attorney_holder_type: 'veteran_service_organization',
                poa_code: accreditation[:accredited_organization_id],
                accredited_individual_registration_number: accreditation[:accredited_individual_id],
                accredited_individual: accredited_representative,
                created_at:
              )
            end
          end
        end

        accreditations
          .uniq { |a| a[:accredited_individual_id] }
          .each_with_index do |accreditation, i|
            claimant_id = Records::CLAIMANTS[i][:id]
            created_at = UNRESOLVED_TIME_TRAVELER.next
            accredited_representative =
              find_accredited_individual(accreditation[:accredited_individual_id])

            id = Records::POA_REQUEST_IDS.next
            unless AccreditedRepresentativePortal::PowerOfAttorneyRequest.exists?(id:)
              poa_forms.push(claimant_poa_forms[claimant_id].dup)
              # NOTE: include an `accredited_individual` and transient `poa_code` so the holder
              # poa code resolves to the seeded organization under both flag states.
              poa_requests.push(
                id:,
                claimant_type: 'veteran',
                claimant_id:,
                power_of_attorney_holder_type: 'veteran_service_organization',
                poa_code: accreditation[:accredited_organization_id],
                accredited_individual_registration_number: accreditation[:accredited_individual_id],
                accredited_individual: accredited_representative,
                created_at:
              )
            end
          end

        inserted_poa_requests =
          insert_all(
            poa_requests,
            factory: [
              :power_of_attorney_request
            ],
            unique_by: :id
          )

        ##
        # Forms and resolutions can't happen in bulk because encryption happens
        # per record unfortunately.
        #
        inserted_poa_requests.each_with_index do |poa_request, i|
          # All need their form.
          poa_forms[i].update!(
            power_of_attorney_request_id: poa_request['id']
          )

          # But not all are resolved.
          next unless resolutions[i]

          FactoryBot.create(
            :power_of_attorney_request_resolution,
            resolution_traits[i],
            power_of_attorney_request_id: poa_request['id'],
            **resolutions[i]
          )
          status = AccreditedRepresentativePortal::PowerOfAttorneyFormSubmission
                   .statuses.keys.sample
          FactoryBot.create(
            :power_of_attorney_form_submission,
            status:,
            power_of_attorney_request_id: poa_request['id']
          )
        end
      end

      def insert_all(records, factory:, unique_by: nil)
        records =
          records.map.with_index do |record, _i|
            yield(record) if block_given?

            FactoryBot
              .build(*factory, **record)
              .attributes
              # This would defeat explicit nils.
              .tap(&:compact!)
          end

        FactoryBot::Internal
          .factory_by_name(factory[0])
          .build_class
          .insert_all(
            records,
            unique_by:
          )
      end

      RESOLUTION_HISTORY_CYCLE =
        %i[expiration declination acceptance]
        .permutation
        .cycle

      RESOLVED_TIME_TRAVELER =
        Enumerator.new do |yielder|
          time = 30.days.ago

          loop do
            ##
            # These 3 entries spread are here because we are making 3 POA
            # requests per claimant in a row.
            #
            yielder << (time + 0.days)
            yielder << (time + 10.days)
            yielder << (time + 20.days)
            time += 6.hours
          end
        end

      UNRESOLVED_TIME_TRAVELER =
        Enumerator.new do |yielder|
          time = 10.days.ago

          loop do
            yielder << time
            time += 6.hours
          end
        end
    end
  end
end
# rubocop:enable Metrics/MethodLength, Metrics/ModuleLength, Rails/SkipsModelValidations
