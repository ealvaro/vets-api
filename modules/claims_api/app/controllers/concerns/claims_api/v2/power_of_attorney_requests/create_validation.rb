# frozen_string_literal: true

require 'brd/brd'

module ClaimsApi
  module V2
    module PowerOfAttorneyRequests
      module CreateValidation
        extend ActiveSupport::Concern

        private

        def validate_country_code
          vet_cc = form_attributes.dig('veteran', 'address', 'countryCode')
          claimant_cc = form_attributes.dig('claimant', 'address', 'countryCode')

          if ClaimsApi::BRD::COUNTRY_CODES[vet_cc.to_s.upcase].blank?
            raise ::Common::Exceptions::UnprocessableEntity.new(
              detail: 'The country provided is not valid.'
            )
          end

          if claimant_cc.present? && ClaimsApi::BRD::COUNTRY_CODES[claimant_cc.to_s.upcase].blank?
            raise ::Common::Exceptions::UnprocessableEntity.new(
              detail: 'The country provided is not valid.'
            )
          end
        end

        def validate_phone_country_code
          %w[veteran claimant].each do |key|
            phone = form_attributes.dig(key, 'phone')
            next if phone.blank?

            validate_phone_details(phone, key)
          end
        end

        def validate_phone_details(phone, key)
          return if phone['phoneNumber'].blank?

          validate_phone_and_country_code_combination_not_valid!(phone, key)
          validate_domestic_country_code_on_international_number!(phone, key)
        end

        def validate_phone_and_country_code_combination_not_valid!(phone_data, key)
          phone_number = phone_data['phoneNumber']&.gsub(/\D/, '')
          country_code = phone_data['countryCode']

          if phone_number.length > 7 && country_code.blank?
            raise ::Common::Exceptions::UnprocessableEntity.new(
              detail: "The #{key}'s international phone number requires a countryCode."
            )
          end
        end

        def validate_domestic_country_code_on_international_number!(phone_data, key)
          phone_number = phone_data['phoneNumber']&.gsub(/\D/, '')
          country_code = phone_data['countryCode']&.gsub(/\D/, '')

          if phone_number.length > 7 && country_code == '1'
            raise ::Common::Exceptions::UnprocessableEntity.new(
              detail: "The #{key}'s countryCode is for a domestic phone number."
            )
          end
        end

        def validate_accredited_representative(poa_code)
          @representative = ClaimsApi::AccreditationTables.representative.where('? = ANY(poa_codes)',
                                                                                poa_code).order(created_at: :desc).first
          # there must be a representative to appoint. This representative can be an accredited attorney, claims agent,
          #   or representative.
          if @representative.nil?
            raise ::Common::Exceptions::ResourceNotFound.new(
              detail: "Could not find an Accredited Representative with poa code: #{poa_code}"
            )
          end
        end

        def validate_accredited_organization(poa_code)
          # organization is not required. An attorney or claims agent appointment request would not have an accredited
          #   organization to associate with.
          @organization = ClaimsApi::AccreditationTables.organization.find_by(poa: poa_code)
        end
      end
    end
  end
end
