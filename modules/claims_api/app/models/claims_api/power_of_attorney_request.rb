# frozen_string_literal: true

require 'claims_api/form_schemas'

module ClaimsApi
  class PowerOfAttorneyRequest < ApplicationRecord
    validates :proc_id, presence: true
    validates :veteran_icn, presence: true
    validates :poa_code, presence: true
    validate :validate_meta_schema

    belongs_to :power_of_attorney, optional: true

    private

    def validate_meta_schema
      ClaimsApi::FormSchemas.new(schema_version: 'v2/power_of_attorney_requests').validate!('METADATA',
                                                                                            metadata_payload)
    rescue JsonSchema::JsonApiMissingAttribute => e
      e.to_json_api[:errors].each do |error|
        errors.add(:metadata, "invalid at #{error[:source]}: #{error[:detail]}")
      end
    end

    def metadata_payload
      return {} if metadata.nil?
      return metadata.deep_stringify_keys if metadata.is_a?(Hash)

      metadata
    end
  end
end
