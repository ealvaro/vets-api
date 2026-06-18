# frozen_string_literal: true

module VeteranStatusCard
  module Constants
    SUPPORT_PHONE = '866-279-3677'
    SUPPORT_HOURS = 'Monday through Friday, 8:00 a.m. to 8:00 p.m. ET.'

    WARNING_STATUS = 'warning'
    ERROR_STATUS = 'error'

    STANDARD_ERROR_TITLE = "You're not eligible for a Veteran Status Card"
    CURRENTLY_SERVING_TITLE = "You can't get a Veteran Status Card while you're on active duty"

    DISCHARGE_STATUS_MESSAGE = [
      {
        type: 'text',
        value: "Your recorded discharge status doesn't meet the requirements for " \
               'this card. Only honorable and general discharges qualify.'
      },
      {
        type: 'link',
        value: 'Learn how to apply for a discharge upgrade or correction',
        url: 'https://www.va.gov/discharge-upgrade-instructions/'
      },
      {
        type: 'text',
        value: "If you think this is incorrect, call us. We're here #{SUPPORT_HOURS}"
      },
      {
        type: 'phone',
        value: SUPPORT_PHONE,
        tty: true
      }
    ].freeze
    DISCHARGE_STATUS_RESPONSE = {
      title: STANDARD_ERROR_TITLE, message: DISCHARGE_STATUS_MESSAGE, status: WARNING_STATUS
    }.freeze

    UNKNOWN_ELIGIBILITY_TITLE = "We don't know if you're eligible for this card"
    UNKNOWN_ELIGIBILITY_MESSAGE = [
      {
        type: 'text',
        value: 'Your record is missing information about your service history or discharge status.'
      },
      {
        type: 'text',
        value: "To fix the issue, call us. We're here #{SUPPORT_HOURS}"
      },
      {
        type: 'phone',
        value: SUPPORT_PHONE,
        tty: true
      }
    ].freeze
    UNKNOWN_ELIGIBILITY_RESPONSE = {
      title: UNKNOWN_ELIGIBILITY_TITLE, message: UNKNOWN_ELIGIBILITY_MESSAGE, status: WARNING_STATUS
    }.freeze

    CURRENTLY_SERVING_MESSAGE = [
      {
        type: 'text',
        value: "If you think this is incorrect based on your service history, call us. We're here #{SUPPORT_HOURS}"
      },
      {
        type: 'phone',
        value: SUPPORT_PHONE,
        tty: true
      }
    ].freeze
    CURRENTLY_SERVING_RESPONSE = {
      title: CURRENTLY_SERVING_TITLE, message: CURRENTLY_SERVING_MESSAGE, status: WARNING_STATUS
    }.freeze

    SOMETHING_WENT_WRONG_TITLE = 'Something went wrong'
    SOMETHING_WENT_WRONG_MESSAGE = [
      {
        type: 'text',
        value: "We're sorry. Something went wrong on our end. Try again later."
      }
    ].freeze
    SOMETHING_WENT_WRONG_RESPONSE = {
      title: SOMETHING_WENT_WRONG_TITLE, message: SOMETHING_WENT_WRONG_MESSAGE, status: ERROR_STATUS
    }.freeze
    PERSON_NOT_FOUND_MESSAGE = [
      {
        type: 'text',
        value: 'Your records are missing from the system.'
      },
      {
        type: 'text',
        value: "To fix the issue, call us. We're here #{SUPPORT_HOURS}"
      },
      {
        type: 'phone',
        value: SUPPORT_PHONE,
        tty: true
      }
    ].freeze
    PERSON_NOT_FOUND_RESPONSE = {
      title: UNKNOWN_ELIGIBILITY_TITLE, message: PERSON_NOT_FOUND_MESSAGE, status: WARNING_STATUS
    }.freeze
  end
end
