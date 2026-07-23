# frozen_string_literal: true

module Pensions
  module PdfFill
    # Helpers used for PDF mapping
    module Helpers
      include ActiveSupport::NumberHelper

      ##
      # Expand full_name
      #
      # @param full_name [Hash]
      #
      # @note Modifies `form_data`
      #
      # @return [Hash] full name
      #
      def expand_full_name(full_name)
        return if full_name.blank?

        middle_initial = full_name['middle']&.first || ''

        full_name['first'] = full_name['first']&.titleize
        full_name['middle'] = middle_initial&.upcase
        full_name['last'] = full_name['last']&.titleize

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

      ##
      # Human readable alias for calling #zero? on a radio value
      #
      # @param value [Object]
      # @param yes_value [Object] default zero
      #
      # @return [Boolean]
      #
      def yes?(value, yes_values = [0])
        value.in?(yes_values)
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
      # @return [String] '1' if truthy, 'Off' if falsy
      #
      def to_checkbox_on_off(value)
        value ? '1' : 'Off'
      end

      ##
      # Convert a given values truthiness to a checkbox on/off version 2
      #
      # @param value [Object]
      #
      # @return [String] 'Yes' if truthy, 'Off' if falsy
      #
      def to_checkbox_on_off_v2(value)
        value ? 'Yes' : 'Off'
      end
    end
  end
end
