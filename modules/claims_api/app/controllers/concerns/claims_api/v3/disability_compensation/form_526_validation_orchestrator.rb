# frozen_string_literal: true

require 'claims_api/v2/disability_compensation_shared_service_module'

module ClaimsApi
  module V3
    module DisabilityCompensation
      class Form526ValidationOrchestrator
        # Orchestrator → Sections → Fields
        #
        # Sections map to top-level schema keys (serviceInformation, veteranIdentification).
        # Section-internal validations (e.g. servicePeriods quantity) live as private methods on the section.
        #
        # Fields are self-contained value objects (Address, ServicePeriod, FullDate, ServiceNumber).
        # Typed by what the value IS, not where it lives in the tree.
        # A field's own validations live as methods on the field itself.
        #
        # Rules are cross-section validations that need data from multiple top-level keys.
        # Examples: ServiceAfter13thBirthday (DOB + service dates), ClaimDateToEndDate (claimDate + exitDate).
        # Called from the orchestrator.

        include ClaimsApi::V2::DisabilityCompensationSharedServiceModule

        def initialize(form_attributes, auth_headers: {})
          @form_attributes = form_attributes
          @auth_headers = auth_headers
        end

        def validate
          return if @form_attributes.empty?

          errors = Errors.new
          claim_date, claim_date_errors = validate_claim_date

          errors.merge(claim_date_errors)
          errors.merge(validate_veteran_identification)
          errors.merge(validate_claim_information)
          errors.merge(validate_service_information)

          validate_claim_date_to_end_date(errors, claim_date)
          validate_service_after_13th_birthday(errors)

          errors.presence
        end

        private

        def validate_veteran_identification
          Sections::VeteranIdentification.new(
            @form_attributes['veteranIdentification'],
            valid_countries:
          ).validate
        end

        def validate_claim_date
          Sections::ClaimDate.new(
            @form_attributes['claimDate']
          ).validate
        end

        def validate_claim_information
          Sections::ClaimInformation.new(
            @form_attributes['claimInformation'],
            brd_lookup:
          ).validate
        end

        def brd_lookup
          @brd_lookup ||= Services::BrdLookup.new
        end

        def validate_service_information
          Sections::ServiceInformation.new(
            @form_attributes['serviceInformation']
          ).validate
        end

        def validate_claim_date_to_end_date(errors, claim_date)
          service_periods = @form_attributes.dig('serviceInformation', 'servicePeriods')
          Rules::ClaimDateToEndDate.call(service_periods, claim_date:, errors:)
        end

        def validate_service_after_13th_birthday(errors)
          service_periods = @form_attributes.dig('serviceInformation', 'servicePeriods')
          birth_date = veteran_birth_date
          return if service_periods.blank? || birth_date.blank?

          service_periods.each_with_index do |sp, idx|
            Rules::ServiceAfter13thBirthday.call(
              sp['entryDate'],
              source: "/serviceInformation/servicePeriods/#{idx}",
              veteran_birth_date: birth_date,
              errors:
            )
          end
        end

        def veteran_birth_date
          form_dob = @form_attributes.dig('veteranIdentification', 'dateOfBirth')
          date = Fields::FullDate.new(form_dob, source: '/veteranIdentification/dateOfBirth')
          return date.parse if date.valid?

          # Auth header DOB is ISO 8601 datetime (e.g. '1976-06-09T00:00:00+00:00')
          @auth_headers['va_eauth_birthdate']&.to_datetime&.to_date
        end
      end
    end
  end
end
