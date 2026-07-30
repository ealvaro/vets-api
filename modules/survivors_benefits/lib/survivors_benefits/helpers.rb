# frozen_string_literal: true

module SurvivorsBenefits
  ##
  # See pdf_fill/forms/va21p8416.rb
  #
  module Helpers
    include ActiveSupport::NumberHelper

    # Small currency lengths
    CURRENCY_LENGTHS_SM = { 'cents' => 2, 'dollars' => 3, 'thousands' => 2 }.freeze

    # Large currency lengths
    CURRENCY_LENGTHS_LG = { 'cents' => 2, 'dollars' => 3, 'thousands' => 3, 'millions' => 2 }.freeze

    # Format a YYYY-MM-DD date string to MM/DD/YYYY
    #
    # @param date_string [String]
    # @return [String]
    #
    def format_date_to_mm_dd_yyyy(date_string)
      return nil if date_string.blank?

      Date.parse(date_string).strftime('%m/%d/%Y')
    end

    # Whether the claim is being filed by a custodian on behalf of a child under 18.
    #
    # @param relationship [String, nil] the form's claimantRelationship
    # @return [Boolean]
    #
    def custodian_filing?(relationship)
      # Section 2 converts raw enum values into humanized radio labels; normalize
      # both forms so this comparison works regardless of expansion order.
      relationship.to_s.upcase.gsub(/\s+/, '_') == 'CUSTODIAN_FILING_FOR_CHILD_UNDER_18'
    end
    module_function :custodian_filing?

    # Returns the PDF field index for claimant-signature/date widgets.
    # Custodian filing for a child under 18 uses the alternate widget set.
    def signature_field_index_for_claimant_relationship(relationship)
      custodian_filing?(relationship) ? 0 : 1
    end
    module_function :signature_field_index_for_claimant_relationship

    ##
    # Splits a currency amount into thousands, dollars, and cents.
    #
    # @param amount [Numeric, nil]
    # @param field_lengths [Hash]
    # @return [Hash]
    #
    def split_currency_amount_sm(amount, field_lengths = {})
      return {} if !amount&.nonzero? || amount.negative? || amount >= 1_000_000

      lengths = CURRENCY_LENGTHS_SM.merge(field_lengths)
      arr = ActiveSupport::NumberHelper.number_to_currency(amount).to_s.split(/[,.$]/).reject(&:empty?)
      amount_hash = {
        'cents' => get_currency_field(arr, -1, lengths['cents']),
        'dollars' => get_currency_field(arr, -2, lengths['dollars']),
        'thousands' => get_currency_field(arr, -3, lengths['thousands'])
      }.compact

      return {} if amount_hash.any? { |k, v| v.size > lengths[k] }

      amount_hash
    end

    ##
    # Splits a currency amount into millions, thousands, dollars, and cents.
    #
    # @param amount [Numeric, nil]
    # @param field_lengths [Hash]
    # @return [Hash]
    #
    def split_currency_amount_lg(amount, field_lengths = {})
      return {} if !amount&.nonzero? || amount.negative? || amount >= 99_999_999

      lengths = CURRENCY_LENGTHS_LG.merge(field_lengths)
      arr = ActiveSupport::NumberHelper.number_to_currency(amount).to_s.split(/[,.$]/).reject(&:empty?)
      amount_hash = {
        'cents' => get_currency_field(arr, -1, lengths['cents']),
        'dollars' => get_currency_field(arr, -2, lengths['dollars']),
        'thousands' => get_currency_field(arr, -3, lengths['thousands']),
        'millions' => get_currency_field(arr, -4, lengths['millions'])
      }.compact

      return {} if amount_hash.any? { |k, v| v.size > lengths[k] }

      amount_hash
    end

    ##
    # Retrieves a specific portion of a currency value and formats it to a fixed length.
    #
    # @param arr [Array<String>]
    # @param neg_i [Integer]
    # @param field_length [Integer]
    # @return [String]
    #
    def get_currency_field(arr, neg_i, field_length)
      value = arr.length >= -neg_i ? arr[neg_i] : nil
      (field_length - value.length).times { value = value.dup.prepend(' ') } if value
      value
    end

    ##
    # Converts a hash's values into a space-separated string.
    #
    # @param hash [Hash]
    # @return [String]
    #
    def change_hash_to_string(hash)
      return '' if hash.blank?

      hash.values.join(' ')
    end

    # Formats name fields for PDF sections.
    # Preserves first and last as provided, reduces middle to an initial,
    # and appends a trimmed suffix to last when present.
    def format_name(name)
      name ||= {}
      first = name['first']
      middle = name['middle']&.strip&.first&.upcase
      last = name['last']
      suffix = name['suffix']&.strip
      last_with_suffix = [last, suffix.presence].compact.join(' ')

      {
        'first' => first,
        'middle' => middle,
        'last' => last_with_suffix.presence || last
      }
    end
  end
end
