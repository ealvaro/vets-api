# frozen_string_literal: true

require 'claims_api/service_branch_mapper'

module ClaimsApi
  module FesMapperBase
    MAX_LINE_LENGTH_ADDRESS_LINE_ONE = 20

    def normalize_claim_date(raw_date)
      # ISO 8601 timestamps include 'T' as the date/time separator (e.g. '2018-08-28T19:53:45+00:00').
      # FES only accepts YYYY-MM-DD, so strip the time component when present.
      # Input is guaranteed valid by schema regex and cast_claim_date! before reaching this point.
      return raw_date unless raw_date.present? && raw_date.include?('T')

      Date.parse(raw_date).strftime('%Y-%m-%d')
    end

    def map_separation_location_code
      @fes_claim[:serviceInformation][:separationLocationCode] = return_separation_location_code
    end

    def return_separation_location_code
      return_most_recent_service_period&.dig(:separationLocationCode)
    end

    def separation_location_code_present?
      return_most_recent_service_period&.dig(:separationLocationCode).present?
    end

    def return_most_recent_service_period
      @data[:serviceInformation][:servicePeriods]&.max_by do |period|
        Date.parse(period[:activeDutyBeginDate])
      end
    end

    def address_line1_too_long?(address)
      ln1 = address[:addressLine1]

      ln1.present? && ln1.length > MAX_LINE_LENGTH_ADDRESS_LINE_ONE
    end

    def transform_address_lines_length(address)
      ln1 = address[:addressLine1]
      ln2 = address[:addressLine2]
      ln3 = address[:addressLine3]

      address[:addressLine3] = "#{ln2} #{ln3}".strip
      address[:addressLine1] = ln1.truncate(MAX_LINE_LENGTH_ADDRESS_LINE_ONE, omission: '', separator: /\s/)
      address[:addressLine2] = ln1.sub(address[:addressLine1], '').strip

      address
    end

    def normalize_service_branch(name)
      ClaimsApi::ServiceBranchMapper.new(name).value
    end

    # claim submission source definition for v1 and v2 to prevent drift between mappers
    def claim_submission_source
      raise NotImplementedError, 'Subclass must define claim_submission_source'
    end
  end
end
