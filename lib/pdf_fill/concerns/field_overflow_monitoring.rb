# frozen_string_literal: true

require 'pdf_fill/hash_converter'
require 'pdf_fill/filler'

##
# Meant to be implemented in after_create callback (see SavedClaim#after_create_metrics).
# Tracks occurences of field and array overflow in merged form data.
#
# @note requires TWO flippers to be enabled:
#   - :saved_claim_pdf_overflow_tracking
#   - :track_pdf_overflow_by_field
#
module PdfFill
  module Concerns
    module FieldOverflowMonitoring
      extend ActiveSupport::Concern

      # StatsD key prefix for overflow monitoring
      STATSD_KEY_PREFIX = 'api.pdf_fill.overflow'

      private

      ##
      # Traverse form data and track which fields and arrays contribute to PDF overflow
      #
      # @see SavedClaim#after_create_metrics
      #
      # @note Should only fire if form instance already confirmed as overflow. See SavedClaim#pdf_overflow_tracking
      #
      # @param form_class [String, nil] optional
      #
      def track_pdf_overflow_by_field(form_class = nil)
        form_class ||= Filler::FORM_CLASSES[form_id]
        return if form_class.blank?

        form = form_class.new(parsed_form)
        key_data = form.try(:key) || form_class::KEY
        check_for_overflow(form.merge_fields, key_data)
      rescue => e
        Rails.logger.error("#{form_id}: Failure in track_pdf_overflow_by_field. #{self.class.name}: #{e.message}")
      end

      ##
      # Recursively traverse every element of form data to identity occurences of overflow
      #
      # @note Unlike PdfFill::Filler#transform_data, this method traverses entire data structure. Goal is not to
      # populate extras page but instead provide statistical insight into high-overflow forms
      #
      # @param form_data [Hash]
      # @param key_data [Hash]
      #
      def check_for_overflow(form_data, key_data)
        return if form_data.blank? || key_data.blank?

        case form_data
        when Hash
          form_data.each do |key, value|
            check_for_overflow(value, key_data[key])
          end
        when Array
          track_array_overflow(key_data) if array_overflow?(form_data, key_data)
          form_data.each { |item| check_for_overflow(item, key_data) }
        else
          track_field_overflow(key_data) if field_overflow?(form_data, key_data)
        end
      end

      ##
      # Check if value has length greater than configured limit
      #
      # @param value [Number, String]
      # @param key_data [Hash]
      #
      # @note Values that cannot be stringified should not have a limit defined
      #
      # @return [Boolean]
      #
      def field_overflow?(value, key_data)
        return false if key_data[:hide_from_overflow] || key_data[:limit].blank?

        value.to_s.length > key_data[:limit]
      end

      def array_overflow?(arr, key_data)
        return false if key_data[:limit].blank?

        return true if key_data[:always_overflow]

        arr.size > key_data[:limit]
      end

      ##
      # Increment metric by individual PDF field when overflowed
      #
      # @param key_data [Hash]
      #
      def track_field_overflow(key_data)
        return if key_data.blank?

        field_key = sanitize(key_data[:key]) || 'unknown'
        tags = ["form_id:#{form_id}", "field:#{field_key}"]
        StatsD.increment("#{STATSD_KEY_PREFIX}.field", tags:)
      end

      ##
      # Increment metric when PDF array field overflowed
      #
      # @param key_data [Hash]
      #
      def track_array_overflow(key_data)
        return if key_data.blank?

        array_key = key_data[:item_label]&.parameterize(separator: '_') || 'unknown'
        tags = ["form_id:#{form_id}", "array:#{array_key}"]
        StatsD.increment("#{STATSD_KEY_PREFIX}.array", tags:)
      end

      ##
      # Remove [%iterator%] suffix from and parameterize string
      #
      # @param key [String]
      #
      # @return [String]
      def sanitize(key)
        return if key.blank?

        key.chomp("[#{HashConverter::ITERATOR}]").parameterize(separator: '_')
      end
    end
  end
end
