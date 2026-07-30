# frozen_string_literal: true

module Mobile
  class SurveyResponse < ApplicationRecord
    has_kms_key
    has_encrypted :survey_data, type: :json, key: :kms_key, **lockbox_options

    VALID_SURVEY_TYPES = %w[giveFeedback intercept].freeze

    validates :survey_type, presence: true, inclusion: { in: VALID_SURVEY_TYPES }
    validates :user_uuid, :survey_data, presence: true

    validate :validate_survey_data_structure
    validate :validate_metadata_structure

    private

    def validate_survey_data_structure
      unless survey_data.is_a?(Hash)
        errors.add(:survey_data, 'must be an object')
        return
      end

      survey_data.each do |key, value|
        unless value.is_a?(Hash)
          errors.add(:survey_data, "question #{key} must be an object")
          next
        end

        required_fields = %w[type label value]
        missing_fields = required_fields - value.keys
        if missing_fields.any?
          errors.add(:survey_data, "question #{key} missing required fields: #{missing_fields.join(', ')}")
        end
      end
    end

    def validate_metadata_structure
      return if metadata.nil?

      errors.add(:metadata, 'must be an object') unless metadata.is_a?(Hash)
    end
  end
end
