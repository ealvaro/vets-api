# frozen_string_literal: true

module Pensions
  module PdfFill
    # Helpers used for PDF mapping
    module Helpers
      include ActiveSupport::NumberHelper

      ##
      # Extracts middle initial from middle name
      #
      # @param full_name [Hash]
      #
      # @note Modifies `form_data`
      #
      # @return [Hash] full name
      #
      def extract_middle_initial(full_name)
        return full_name if full_name.blank?

        full_name['middle'] = full_name['middle']&.first || ''

        full_name
      end

      ##
      # Convert a given values truthiness to a radio yes/no
      #
      # @param value [Object]
      #
      # @return [Integer] zero or one
      #
      def to_radio_yes_no(value)
        value ? 0 : 1
      end

      # Default yes values for #yes? helper
      DEFAULT_YES_VALUES = [0, 'Yes'].freeze

      ##
      # V2: Human readable alias for calculating if checkbox or radio marked yes
      #
      # @param value [Object]
      #
      # @return [Boolean]
      #
      def yes?(value)
        value.in?(DEFAULT_YES_VALUES)
      end

      ##
      # Convert a date to a string formatted as month-day-year
      #
      # @param date [Object]
      #
      # @return [String, nil] formatted date string or nil if invalid
      #
      def to_date_string(date)
        date_hash = split_date(date)
        return unless date_hash

        "#{date_hash['month']}-#{date_hash['day']}-#{date_hash['year']}"
      end

      ##
      # Build a date range string from a date range object
      #
      # @param date_range [Hash] hash containing 'from' and 'to' date keys
      #
      # @return [String] formatted date range string
      #
      def build_date_range_string(date_range)
        "#{to_date_string(date_range['from'])} - #{to_date_string(date_range['to']) || 'No End Date'}"
      end

      ##
      # Ensure trailing zeroes not cut off from floats when stringified
      #
      # @param amount [Float, Object]
      #
      # @return [String, Object] formatted currency string or original amount
      #
      def expand_currency(amount)
        return amount unless amount.is_a?(Float)

        format('%.2f', amount)
      end

      ##
      # Split up currency amounts to three parts
      #
      # @param amount [Numeric, nil]
      #
      # @return [Hash] split currency parts and cents
      #
      def split_currency_amount(amount)
        return {} if amount.nil? || amount.negative? || amount >= 10_000_000

        number_map = {
          1 => 'one',
          2 => 'two',
          3 => 'three'
        }

        arr = number_to_currency(amount).to_s.split(/[,.$]/).reject(&:empty?)
        split_hash = { 'part_cents' => arr.last }
        arr.pop
        arr.each_with_index { |x, i| split_hash["part_#{number_map[arr.length - i]}"] = x }
        split_hash
      end

      ##
      # Convert a given values truthiness to a checkbox on/off
      #
      # @param value [Object]
      #
      # @return [String] '1' or 'Yes' if truthy, 'Off' if falsy
      #
      def to_checkbox_on_off(value)
        yes_or_one = Pensions.use_v2? ? 'Yes' : '1'
        value ? yes_or_one : 'Off'
      end

      ##
      # Handles street address overflow by combining street lines if limits are exceeded
      # or if a third street line is present
      #
      # @param address [Hash] The veteran's address hash containing street fields
      # @param limit [Array<Integers>]
      #
      # @return [Hash, nil] The updated address hash with combined street lines if overflow occurs,
      #                     or nil if the address is blank
      #
      # @note This method modifies the `address` hash in place
      #
      def handle_street_overflow(address, *limits)
        return if address.blank?

        street_limit, street_limit2 = limits

        return if street_limit.blank? || street_limit2.blank?

        street, street2, street3 = address.values_at('street', 'street2', 'street3')

        if street3.present? ||
           street&.length&.>(street_limit) ||
           street2&.length&.>(street_limit2)
          address.merge!(
            {
              'street' => nil,
              'street2' => nil,
              'street3' => [street, street2, street3].compact.join("\n")
            }
          )
        else
          address.delete('street3')
        end
      end
    end
  end
end
