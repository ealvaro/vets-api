# frozen_string_literal: true

module IvcChampva
  class FormFieldTransliterator
    FIELD_PATTERNS = [
      /street/i, /city/i, /state/i, /country/i, /postal_code/i,
      /^.*_address$/i, /^.*_address_string$/i, /address$/i
    ].freeze

    SKIP_KEYS = %w[email_address applicant_email_address].freeze

    def self.transliterate_all!(data)
      FieldTransliterator.transliterate_all!(data, field_patterns: FIELD_PATTERNS, skip_keys: SKIP_KEYS)
    end
  end
end
