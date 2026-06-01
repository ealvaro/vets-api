# frozen_string_literal: true

module Swagger
  module Schemas
    class UploadSupportingEvidence
      include Swagger::Blocks

      swagger_schema :UploadSupportingEvidence do
        property :data, type: :object do
          property :attributes, type: :object do
            key :required, %i[guid]
            property :guid, type: :string, example: '3c05b2f0-0715-4298-965d-f733465ed80a'
            property :warnings, type: :array,
                                description: 'Present only when attachment_id is provided and the ' \
                                             'disability_526_document_validation_enabled feature flag is active. ' \
                                             'Empty array means no issues detected.' do
              items type: :string, enum: %w[wrong_form unable_to_validate]
            end
          end
          property :id, type: :string, example: '11'
          property :type, type: :string, example: 'supporting_evidence_attachments'
        end
      end
    end
  end
end
