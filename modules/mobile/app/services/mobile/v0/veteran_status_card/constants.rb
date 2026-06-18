# frozen_string_literal: true

require 'veteran_status_card/constants'

module Mobile
  module V0
    module VeteranStatusCard
      module Constants
        SUPPORT_PHONE = ::VeteranStatusCard::Constants::SUPPORT_PHONE
        SUPPORT_HOURS = ::VeteranStatusCard::Constants::SUPPORT_HOURS

        WARNING_STATUS = ::VeteranStatusCard::Constants::WARNING_STATUS
        ERROR_STATUS = ::VeteranStatusCard::Constants::ERROR_STATUS

        STANDARD_ERROR_TITLE = ::VeteranStatusCard::Constants::STANDARD_ERROR_TITLE
        CURRENTLY_SERVING_TITLE = ::VeteranStatusCard::Constants::CURRENTLY_SERVING_TITLE
        UNKNOWN_ELIGIBILITY_TITLE = ::VeteranStatusCard::Constants::UNKNOWN_ELIGIBILITY_TITLE

        DISCHARGE_STATUS_RESPONSE = {
          title: STANDARD_ERROR_TITLE,
          message: ::VeteranStatusCard::Constants::DISCHARGE_STATUS_MESSAGE,
          status: WARNING_STATUS
        }.freeze

        UNKNOWN_ELIGIBILITY_RESPONSE = {
          title: UNKNOWN_ELIGIBILITY_TITLE,
          message: ::VeteranStatusCard::Constants::UNKNOWN_ELIGIBILITY_MESSAGE,
          status: WARNING_STATUS
        }.freeze

        CURRENTLY_SERVING_RESPONSE = {
          title: CURRENTLY_SERVING_TITLE,
          message: ::VeteranStatusCard::Constants::CURRENTLY_SERVING_MESSAGE,
          status: WARNING_STATUS
        }.freeze

        SOMETHING_WENT_WRONG_RESPONSE = {
          title: ::VeteranStatusCard::Constants::SOMETHING_WENT_WRONG_TITLE,
          message: ::VeteranStatusCard::Constants::SOMETHING_WENT_WRONG_MESSAGE,
          status: ERROR_STATUS
        }.freeze

        PERSON_NOT_FOUND_RESPONSE = {
          title: UNKNOWN_ELIGIBILITY_TITLE,
          message: ::VeteranStatusCard::Constants::PERSON_NOT_FOUND_MESSAGE,
          status: WARNING_STATUS
        }.freeze
      end
    end
  end
end
