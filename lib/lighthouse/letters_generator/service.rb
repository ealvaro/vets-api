# frozen_string_literal: true

require 'lighthouse/letters_generator/configuration'
require 'lighthouse/letters_generator/content'
require 'lighthouse/letters_generator/service_error'
require 'lighthouse/service_exception'
require 'common/exceptions/bad_request'

module Lighthouse
  module LettersGenerator
    def self.measure_time(msg)
      start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)

      response = yield

      end_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      elapsed = end_time - start_time

      Rails.logger.info "#{msg}: #{elapsed} seconds"
      response
    end

    class Service < Common::Client::Base
      # TODO: Remove once cst_letters_description_content_format is fully enabled and all clients
      # have migrated to the new description shape.
      CONSOLIDATED_COVERAGE_NAME = 'Creditable coverage for health care and prescription drugs'

      BENEFICIARY_KEY_TRANFORMS = {
        awardEffectiveDateTime: :awardEffectiveDate,
        chapter35Eligibility: :hasChapter35Eligibility,
        nonServiceConnectedPension: :hasNonServiceConnectedPension,
        serviceConnectedDisabilities: :hasServiceConnectedDisabilities,
        adaptedHousing: :hasAdaptedHousing,
        individualUnemployabilityGranted: :hasIndividualUnemployabilityGranted,
        specialMonthlyCompensation: :hasSpecialMonthlyCompensation
      }.freeze

      configuration Lighthouse::LettersGenerator::Configuration

      def get_letter(icn, letter_type, options = {})
        endpoint = "letter-contents/#{letter_type}"
        log = "Retrieving letter from #{config.generator_url}/#{endpoint}"
        params = { icn: }.merge(options)

        response = get_from_lighthouse(endpoint, params, log)
        response.body
      end

      # apply_content_updates controls whether this caller receives the updated letter content:
      # pass false to force the legacy payload regardless of the Flipper flag (mobile uses this to
      # suppress updates on older app versions). Defaults to true, so other callers are unaffected.
      def get_eligible_letter_types(icn, user = nil, apply_content_updates: true)
        endpoint = 'eligible-letters'
        log = "Retrieving eligible letter types and destination from #{config.generator_url}/#{endpoint}"
        params = { icn: }

        response = get_from_lighthouse(endpoint, params, log)
        {
          letters: transform_letters(response.body['letters'], user, apply_content_updates:),
          letter_destination: response.body['letterDestination']
        }
      end

      def get_benefit_information(icn)
        endpoint = 'eligible-letters'
        log = "Retrieving benefit information from #{config.generator_url}/#{endpoint}"
        params = { icn: }

        response = get_from_lighthouse(endpoint, params, log)
        {
          benefitInformation: transform_benefit_information(response.body['benefitInformation']),
          militaryService: transform_military_services(response.body['militaryServices'])
        }
      end

      def download_letter(icns, letter_type, options = {})
        endpoint = "letters/#{letter_type}/letter"
        log = "Downloading letter from #{config.generator_url}/#{endpoint}"
        params = icns.merge(options)

        response = get_from_lighthouse(endpoint, params, log)
        response.body
      end

      def valid_type?(letter_type, user = nil)
        letter_types(user).include? letter_type.downcase
      end

      private

      def letter_types(user = nil)
        list = %w[
          benefit_summary
          benefit_summary_dependent
          benefit_verification
          certificate_of_eligibility
          civil_service
          commissary
          medicare_partd
          minimum_essential_coverage
          proof_of_service
          service_verification
        ]
        list = list.excluding('service_verification') if Flipper.enabled?(:letters_hide_service_verification_letter)

        if Flipper.enabled?(:letters_hide_dependent_benefits_summary_letter)
          list = list.excluding('benefit_summary_dependent')
        end

        list << 'foreign_medical_program' if fmp_benefits_authorization_letter_enabled?(user)
        list.to_set.freeze
      end

      def fmp_benefits_authorization_letter_enabled?(user = nil)
        return Flipper.enabled?(:fmp_benefits_authorization_letter) if user.blank?

        Flipper.enabled?(:fmp_benefits_authorization_letter, user)
      end

      def get_from_lighthouse(endpoint, params, log)
        Lighthouse::LettersGenerator.measure_time(log) do
          config.connection.get(
            endpoint,
            params,
            { Authorization: "Bearer #{config.get_access_token}" }
          )
        end
      rescue Faraday::ClientError, Faraday::ServerError => e
        handle_error(e, config.service_name, endpoint)
      end

      def handle_error(error, lighthouse_client_id, endpoint)
        Lighthouse::ServiceException.send_error(
          error,
          self.class.to_s.underscore,
          lighthouse_client_id,
          "#{config.generator_url}/#{endpoint}"
        )
      end

      def transform_letters(letters, user = nil, apply_content_updates: true)
        filtered_letters = letters.select { |l| valid_type?(l['letterType'], user) }
        show_updated_content = content_updates_enabled?(user) && apply_content_updates

        if show_updated_content
          letters_to_transform =
            if description_content_format_enabled?
              consolidate_coverage_letters(filtered_letters)
            else
              filtered_letters
            end

          sort_letters_by_order(updated_letter_transformation(letters_to_transform))
        else
          filtered_letters.map do |letter|
            {
              letterType: letter['letterType'].downcase,
              name: letter['letterName']
            }
          end
        end
      end

      def consolidate_coverage_letters(letters)
        relabeled = letters.map do |l|
          l['letterType'].downcase == 'medicare_partd' ? l.merge('letterType' => 'minimum_essential_coverage') : l
        end
        relabeled.uniq { |l| l['letterType'].downcase }
      end

      def updated_letter_transformation(letters)
        letters.map do |letter|
          letter_type_lower = letter['letterType'].downcase
          {
            letterType: letter_type_lower,
            name: letter_name(letter_type_lower, letter['letterName']),
            description: Lighthouse::LettersGenerator.format_description(letter_type_lower)
          }
        end
      end

      def letter_name(letter_type, upstream_name)
        if letter_type == 'minimum_essential_coverage' && description_content_format_enabled?
          CONSOLIDATED_COVERAGE_NAME
        else
          Content::LETTER_NAME_OVERRIDES[letter_type] || upstream_name
        end
      end

      def sort_letters_by_order(transformed_letters)
        sorted_by_order = Content::LETTER_ORDER.filter_map do |letter_type|
          transformed_letters.find { |letter| letter[:letterType] == letter_type }
        end

        remaining_letters = transformed_letters.reject do |letter|
          sorted_by_order.any? { |sorted| sorted[:letterType] == letter[:letterType] }
        end

        sorted_by_order + remaining_letters
      end

      def content_updates_enabled?(user)
        Flipper.enabled?(:cst_letters_content_updates, user)
      end

      def description_content_format_enabled?
        Flipper.enabled?(:cst_letters_description_content_format)
      end

      def transform_military_services(services_info)
        services_info.map do |service|
          service[:enteredDate] = service.delete 'enteredDateTime'
          service[:releasedDate] = service.delete 'releasedDateTime'

          service.transform_keys(&:to_sym)
        end
      end

      def transform_benefit_information(info)
        symbolized_info = info.deep_transform_keys(&:to_sym)

        transformed_info = symbolized_info.reduce({}) do |acc, (k, v)|
          if BENEFICIARY_KEY_TRANFORMS.key? k
            acc.merge({ BENEFICIARY_KEY_TRANFORMS[k] => v })
          else
            acc.merge({ k => v })
          end
        end

        monthly_award_amount = symbolized_info[:monthlyAwardAmount] ? symbolized_info[:monthlyAwardAmount][:value] : 0

        # Don't return chapter35EligibilityDateTime
        # It's not currently (June 2023) used on the frontend, and in fact causes problems
        transformed_info
          .merge({ monthlyAwardAmount: monthly_award_amount })
          .except(:chapter35EligibilityDateTime)
      end

      def create_invalid_type_error(letter_type)
        error = {}
        error['title'] = 'Invalid letter type'
        error['message'] = "Letter type of #{letter_type.downcase} is not one of the expected options"
        error['status'] = 400

        error
      end
    end
  end
end
