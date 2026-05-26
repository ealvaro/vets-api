# frozen_string_literal: true

# Shared regular expressions and allowed values for inbound form validation (COE, etc.).
module Common
  module ValidationsPatterns
    # Two-letter codes used in COE v2 address fields (US states, DC, and common territories / military).
    COE_STATE_CODES = %w[
      AL AK AZ AR CA CO CT DE DC FL GA
      HI ID IL IN IA KS KY LA ME MD MA
      MI MN MS MO MT NE NV NH NJ NM NY
      NC ND OH OK OR PA RI SC SD TN TX
      UT VT VA WA WV WI WY
      AS GU MP PR VI
      AP AE AA
    ].freeze

    # YYYY-MM-DD; also used for loose date checks alongside ISO8601 in COE dateRange validation.
    COE_DATE_OF_BIRTH_PATTERN = /
      \A
      (?:19|20)\d{2}-
      (?:0[1-9]|1[0-2])-
      (?:0[1-9]|[12]\d|3[01])
      \z
    /x

    COE_POSTAL_CODE_PATTERN = /\A\d{5}(-\d{4})?\z/
  end
end
