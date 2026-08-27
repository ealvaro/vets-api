# frozen_string_literal: true

require 'pdf_fill/hash_converter'
require 'pdf_fill/filler'

##
# Tracks PDF overflow as well as individual occurences of field and array overflow in merged form data.
#
# @note associated feature toggles:
#   - :saved_claim_pdf_overflow_tracking
#   - :track_pdf_overflow_by_field
#
module PdfFill
  class OverflowTracker
    def initialize(claim)
      @claim = claim
      @form_class = Filler::FORM_CLASSES[@claim&.form_id]
      raise ArgumentError, 'No form class associated with claim' if @form_class.blank?
    end

    def track_pdf_overflow(filename)
      return false unless filename&.end_with?('_final.pdf')

      tags = ["form_id:#{@claim.form_id}", "doctype:#{@claim.document_type}"]
      StatsD.increment('saved_claim.pdf.overflow', tags:)
      true
    rescue => e
      Rails.logger.error("#{@claim.form_id}: Failure in track_pdf_overflow", saved_claim_id: @claim.id, error: e)
      false
    end

    ##
    # StatsD key prefix for overflow monitoring
    #
    # @note: StatsD namespaces diverge between #track_pdf_overflow and #track_pdf_overflow_by_field for reasons
    #        of backwards compatibility
    #
    STATSD_KEY_PREFIX = 'api.pdf_fill.overflow'

    ##
    # Traverse form data and track which fields and arrays contribute to PDF overflow
    #
    # @note No necessary to call unless form instance already confirmed as overflow
    #
    # @param form_class [String, nil] optional
    #
    def track_pdf_overflow_by_field
      form = @form_class.new(@claim.parsed_form)
      key_data = form.try(:key) || @form_class::KEY
      check_for_overflow(form.merge_fields, key_data) # recursive
    rescue => e
      Rails.logger.error("#{@claim.form_id}: Failure in track_pdf_overflow_by_field", saved_claim_id: @claim.id,
                                                                                      error: e)
    end

    private

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
      tags = ["form_id:#{@claim.form_id}", "field:#{field_key}"]
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
      tags = ["form_id:#{@claim.form_id}", "array:#{array_key}"]
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
