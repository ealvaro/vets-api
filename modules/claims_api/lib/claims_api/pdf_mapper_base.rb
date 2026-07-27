# frozen_string_literal: true

require 'claims_api/v2/error/lighthouse_error_handler'

module ClaimsApi
  module PdfMapperBase
    YYYYMMDD_REGEX = /(?<year>\d{4})(?:-(?<month>\d{2}))?(?:-(?<day>\d{2}))?/
    MMDDYYYY_REGEX = /(?<month>\d{2})?(?:-(?<day>\d{2}))?-?(?<year>\d{4})/
    CLAIM_DATE_FORMAT = '%Y-%m-%d'
    BDD_PROGRAM_CLAIM = 'BDD_PROGRAM_CLAIM'

    def date_signed(claim_date)
      claim_date_value = extract_date_safely(claim_date)
      unless valid_date?(claim_date_value)
        raise ::ClaimsApi::Common::Exceptions::Lighthouse::UnprocessableEntity.new(
          detail: 'Invalid claim date provided'
        )
      end

      Date.parse(claim_date_value)
    end

    def extract_date_safely(date_input)
      return nil if date_input.blank?

      date_string = determine_date_string_value(date_input)
      if date_string.include?('T') # schema suggests this format, but does not enforce it enough for us to trust
        date_string.split('T').first
      else
        date_string
      end
    end

    def determine_date_string_value(date_input)
      case date_input
      when Date, Time, DateTime then date_input.to_date.iso8601
      else date_input.to_s
      end
    end

    def valid_date?(date_string)
      return false if date_string.blank?

      Date.strptime(date_string, CLAIM_DATE_FORMAT)
      true
    rescue Date::Error, TypeError
      false
    end

    def concatenate_address(address_line_one, address_line_two, address_line_three = nil)
      [address_line_one, address_line_two, address_line_three].compact.map(&:strip).reject(&:empty?).join(' ')
    end

    def concatenate_zip_code(nested_address_object)
      return nested_address_object&.dig('internationalPostalCode') unless nested_address_object&.dig('country') == 'USA'

      zip_first_five = nested_address_object['zipFirstFive']&.to_s
      zip_last_four  = nested_address_object['zipLastFour']
      zip_last_four.present? ? "#{zip_first_five}-#{zip_last_four}" : zip_first_five.presence
    end

    def format_ssn(ssn)
      "#{ssn[0..2]}-#{ssn[3..4]}-#{ssn[5..8]}"
    end

    def format_birth_date(birth_date_data)
      { month: birth_date_data[5..6].to_s, day: birth_date_data[8..9].to_s, year: birth_date_data[0..3].to_s }
    end

    def make_date_string_month_first(date, date_length)
      year, month, day = regex_date_conversion(date)
      return if year.nil? || date_length.nil?

      if date_length == 4
        year.to_s
      elsif date_length == 7
        "#{month}/#{year}"
      else
        "#{month}/#{day}/#{year}"
      end
    end

    def make_date_object(date, date_length)
      year, month, day = regex_date_conversion(date)
      return if year.nil? || date_length.nil?

      if date_length == 4
        { year: }
      elsif date_length == 7
        { month:, year: }
      else
        { year:, month:, day: }
      end
    end

    def regex_date_conversion(date)
      if date.present?
        date_match = extract_ymd_or_mdy_format(date)
        date_match&.values_at(:year, :month, :day)
      end
    end

    def extract_ymd_or_mdy_format(date)
      date.match(/\A(?:#{YYYYMMDD_REGEX}|#{MMDDYYYY_REGEX})?\z/)
    end

    def format_country(country)
      country == 'USA' ? 'US' : country
    end

    def convert_phone(phone)
      phone&.gsub!(/[^0-9]/, '')
      return nil if phone.nil? || (phone.length < 10)

      return "#{phone[0..2]}-#{phone[3..5]}-#{phone[6..9]}" if phone.length == 10

      "#{phone[0..1]}-#{phone[2..3]}-#{phone[4..7]}-#{phone[8..11]}" if phone.length > 10
    end

    # exposure is not used in v1
    def build_disability_item(disability, approximate_date, service_relevance, exposure = nil)
      { disability:, approximateDate: approximate_date, exposureOrEventOrInjury: exposure,
        serviceRelevance: service_relevance }.compact
    end

    def handle_yes_no(pay)
      pay ? 'YES' : 'NO'
    end
  end
end
