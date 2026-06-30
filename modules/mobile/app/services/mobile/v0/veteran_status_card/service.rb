# frozen_string_literal: true

require 'veteran_status_card/service'
require 'mobile/v0/veteran_status_card/constants'

module Mobile
  module V0
    module VeteranStatusCard
      ##
      # Mobile-specific service for generating Veteran Status Card data
      # Inherits from VeteranStatusCard::Service and overrides response methods
      # to use mobile-specific constants and messaging
      #
      class Service < ::VeteranStatusCard::Service
        def status_card
          # Manually raise a response for testing purposes when a specific user is in non-production environments
          if Settings.vsp_environment&.to_s&.downcase != 'production' && @user&.email == 'vets.gov.user+9@gmail.com'
            @confirmation_status = PERSON_NOT_FOUND_MESSAGE
            return person_not_found_response_hash
          end

          super
        end

        protected

        ##
        # @see VeteranStatusCard::Service#statsd_key_prefix
        # @return [String] mobile-specific StatsD key prefix
        #
        def statsd_key_prefix
          'veteran_status_card.mobile'
        end

        ##
        # @see VeteranStatusCard::Service#service_name
        # @return [String] mobile-specific service name for logging
        #
        def service_name
          '[Mobile::V0::VeteranStatusCard::Service]'
        end

        ##
        # @see VeteranStatusCard::Service#something_went_wrong_response
        # @return [Hash] mobile-specific something went wrong response
        #
        def something_went_wrong_response
          @user_message = SOMETHING_WENT_WRONG_MESSAGE
          Mobile::V0::VeteranStatusCard::Constants::SOMETHING_WENT_WRONG_RESPONSE
        end

        ##
        # @see VeteranStatusCard::Service#discharge_status_response
        # @return [Hash] mobile-specific discharge status response
        #
        def discharge_status_response
          @user_message = DISCHARGE_STATUS_MESSAGE
          Mobile::V0::VeteranStatusCard::Constants::DISCHARGE_STATUS_RESPONSE
        end

        ##
        # @see VeteranStatusCard::Service#unknown_eligibility_response
        # @return [Hash] mobile-specific unknown eligibility response
        #
        def unknown_eligibility_response
          @user_message = UNKNOWN_ELIGIBILITY_MESSAGE
          Mobile::V0::VeteranStatusCard::Constants::UNKNOWN_ELIGIBILITY_RESPONSE
        end

        ##
        # @see VeteranStatusCard::Service#currently_serving_response
        # @return [Hash] mobile-specific currently serving response
        #
        def currently_serving_response
          @user_message = CURRENTLY_SERVING_MESSAGE
          Mobile::V0::VeteranStatusCard::Constants::CURRENTLY_SERVING_RESPONSE
        end

        ##
        # @see VeteranStatusCard::Service#person_not_found_response
        # @return [Hash] mobile-specific person not found response
        #
        def person_not_found_response
          @user_message = PERSON_NOT_FOUND_MESSAGE
          Mobile::V0::VeteranStatusCard::Constants::PERSON_NOT_FOUND_RESPONSE
        end
      end
    end
  end
end
