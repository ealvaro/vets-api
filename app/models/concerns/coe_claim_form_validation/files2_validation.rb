# frozen_string_literal: true

module CoeClaimFormValidation
  module Files2Validation
    extend ActiveSupport::Concern

    # Loosely matches type/subtoken shape (e.g. application/pdf, image/jpeg).
    MIME_TYPE_PATTERN = %r{\A[\w\#$&^.+!*-]+/[\w\#$&^.+!*-]+\z}i

    private

    def validate_files2
      return unless parsed_form.key?('files2')

      files = parsed_form['files2']
      unless files.is_a?(Array)
        errors.add('/files2', 'must be an array')
        return
      end
      files.each_with_index { |file, i| validate_single_form_file2(file, i) }
    end

    def validate_single_form_file2(file, i)
      base = "/files2/#{i}"
      unless file.is_a?(Hash)
        errors.add(base, 'must be an object')
        return
      end

      %w[guid confirmationCode type].each { |key| validate_required_string(file[key], "#{base}/#{key}") }
      if file['type'].is_a?(String) && file['type'].present? && !file['type'].match?(MIME_TYPE_PATTERN)
        errors.add("#{base}/type", 'must be a valid MIME type')
      end

      validate_file2_additional_data(file, base)
      validate_file2_optional_metadata(file, base)
    end

    def validate_file2_additional_data(file, base)
      return unless file.key?('additionalData')

      ad = file['additionalData']
      if ad.present? && !ad.is_a?(Hash)
        errors.add("#{base}/additionalData", 'must be an object')
        return
      end

      return unless ad.is_a?(Hash) && ad.key?('attachmentType') && ad['attachmentType'].present?

      validate_optional_string(ad['attachmentType'], "#{base}/additionalData/attachmentType")
    end

    def validate_file2_optional_metadata(file, base)
      validate_optional_string(file['name'], "#{base}/name") if file.key?('name') && file['name'].present?
      return unless file.key?('size')
      return if file['size'].nil? || file['size'].is_a?(Integer)

      errors.add("#{base}/size", 'must be an integer')
    end
  end
end
