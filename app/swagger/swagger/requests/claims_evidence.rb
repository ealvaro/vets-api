# frozen_string_literal: true

module Swagger
  module Requests
    class ClaimsEvidence
      include Swagger::Blocks

      swagger_path '/v0/claims_evidence' do
        operation :post do
          extend Swagger::Responses::AuthenticationError
          extend Swagger::Responses::BadRequestError
          extend Swagger::Responses::ForbiddenError
          extend Swagger::Responses::UnprocessableEntityError
          extend Swagger::Responses::ServiceUnavailableError

          key :description, 'Upload a supplemental claim evidence file to the veteran\'s VA eFolder'
          key :operationId, 'uploadClaimsEvidence'
          key :tags, %w[claims_evidence]
          key :consumes, %w[multipart/form-data]

          parameter :authorization

          parameter do
            key :name, :file
            key :in, :formData
            key :description, 'The evidence file to upload'
            key :required, true
            key :type, :file
          end

          parameter do
            key :name, :documentTypeId
            key :in, :formData
            key :description, 'Claims Evidence document type ID identifying the type of evidence being uploaded'
            key :required, true
            key :type, :integer
          end

          parameter do
            key :name, :supplementalClaimId
            key :in, :formData
            key :description, 'Caseflow supplemental claim identifier (e.g. "SC10879") the upload is associated with'
            key :required, true
            key :type, :string
          end

          response 200 do
            key :description, 'File uploaded successfully; returns the Claims Evidence file UUID'
            schema do
              key :type, :object
              property :uuid, type: :string, example: 'c30626c9-954d-4dd1-9f70-1e38756d9d97'
              property :currentVersionUuid, type: :string, example: 'c30626c9-954d-4dd1-9f70-1e38756d9d98'
            end
          end

          response 404 do
            key :description, 'Endpoint not found (feature flag disabled)'
            schema do
              key :$ref, :Errors
            end
          end
        end
      end
    end
  end
end
