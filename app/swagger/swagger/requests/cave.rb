# frozen_string_literal: true

module Swagger
  module Requests
    class Cave
      include Swagger::Blocks

      swagger_schema :CaveIntakeRequest do
        key :required, %i[pdf_b64 file_name]

        property :pdf_b64,
                 type: :string,
                 description: 'Base64-encoded PDF contents to submit to the document processing pipeline',
                 example: 'JVBERi0xLjQKJcfs...'
        property :file_name,
                 type: :string,
                 description: 'Original filename forwarded to the upstream intake service',
                 example: 'test.pdf'
      end

      swagger_schema :CaveIntakeResponse do
        key :required, [:id]

        property :id, type: :string, example: 'abc123'
      end

      swagger_schema :CaveStatusResponse do
        key :required, [:scan_status]
        key :description, <<~DESC
          Envelope-bearing CAVE response. `scan_status` is the shared failure contract and is
          always one of four values. ALL four are returned as HTTP 200 with this body; the
          failure/partial-success is conveyed in the body (not via an HTTP error status) so the
          frontend poller can stop on a terminal `scan_status`:
            - `pending`               processing has not finished
            - `completed`             processing succeeded
            - `completed_with_errors` processing finished but returned recoverable `warnings`
            - `failed`                processing failed (terminal); `error` describes the failure

          HTTP 502 is reserved for transport-level problems (upstream unreachable/error) and for
          a missing/unrecognized `scan_status` or malformed payload — never for a valid `failed`.
        DESC

        property :id, type: :string, example: 'abc123'
        property :scan_status,
                 type: :string,
                 enum: %w[pending completed completed_with_errors failed],
                 example: 'completed'
        # Present when scan_status is `failed`; passed through unchanged in the 200 body so the
        # frontend can surface the failure detail. NOT converted to an HTTP error status.
        property :error, type: :object do
          key :description, 'Present when scan_status is `failed`; describes the failure.'
          property :scan_status, type: :string, example: 'failed'
          property :step, type: :string, example: 'classification'
          property :error_type, type: :string, example: 'processing_error'
          property :error_message, type: :string, example: 'Unable to classify document'
        end
        # Present when scan_status is `completed_with_errors`; recoverable, non-fatal issues.
        property :warnings do
          key :type, :array
          key :description, 'Present when scan_status is `completed_with_errors`; recoverable issues.'
          items do
            key :type, :object
            property :step, type: :string, example: 'extraction'
            property :warning_type, type: :string, example: 'low_confidence_field'
            property :warning_message, type: :string, example: 'Low confidence on DATE_OF_BIRTH'
          end
        end
      end

      swagger_schema :CaveOutputResponse do
        key :description, <<~DESC
          Extracted `forms` payload from the upstream document processor. Payload shape varies by
          document type. Unlike CaveStatusResponse this is NOT the doc-status envelope: it carries
          no top-level `scan_status`. vets-api validates the payload shape (a non-empty object) and
          returns HTTP 502 if the upstream returns an unusable body.
        DESC

        property :forms do
          key :type, :array
          items do
            property :mmsFormValidationId, type: :string, example: 'form-kvp-123'
            property :mmsArtifactValidationId, type: :string, example: 'artifact-kvp-456'
          end
        end
      end

      swagger_schema :CaveKeyValuePayload do
        key :description, 'Arbitrary JSON object associated with a KVP identifier.'

        property :FIRST_NAME, type: :string, example: 'Ada'
        property :LAST_NAME, type: :string, example: 'Lovelace'
      end

      swagger_schema :CaveDiffRequest do
        key :required, %i[lhs rhs]

        property :lhs, type: :object, description: 'Original JSON object to compare'
        property :rhs, type: :object, description: 'Updated JSON object to compare'
      end

      swagger_schema :CaveDiffResponse do
        key :required, %i[is_different diff]

        property :is_different, type: :boolean, example: true
        property :diff do
          key :type, :array
          items do
            key :type, :object
            property :first_name, type: :object do
              property :lhs, type: :string, example: 'jee'
              property :rhs, type: :string, example: 'john'
              property :is_different, type: :boolean, example: true
            end
          end
        end
      end

      swagger_schema :CaveServiceUnavailable do
        key :required, [:errors]

        property :errors do
          key :type, :array
          items do
            key :$ref, :Error
          end
        end
      end

      swagger_path '/v0/cave' do
        operation :post do
          extend Swagger::Responses::AuthenticationError
          extend Swagger::Responses::BadRequestError
          extend Swagger::Responses::ForbiddenError

          key :description, 'Submit a PDF to the CAVE document processing proxy'
          key :operationId, 'createCaveDocument'
          key :tags, %w[cave]
          key :consumes, ['application/json']
          key :produces, ['application/json']

          parameter :authorization

          parameter do
            key :name, :document
            key :in, :body
            key :description, 'Document intake payload'
            key :required, true
            schema do
              key :$ref, :CaveIntakeRequest
            end
          end

          response 200 do
            key :description, 'Document accepted for processing'
            schema do
              key :$ref, :CaveIntakeResponse
            end
          end

          response 502 do
            key :description, 'Document processing service unavailable'
            schema do
              key :$ref, :CaveServiceUnavailable
            end
          end
        end
      end

      swagger_path '/v0/cave/{id}/status' do
        operation :get do
          extend Swagger::Responses::AuthenticationError
          extend Swagger::Responses::ForbiddenError

          key :description, 'Get the current processing status for a submitted document'
          key :operationId, 'getCaveDocumentStatus'
          key :tags, %w[cave]
          key :produces, ['application/json']

          parameter :authorization

          parameter do
            key :name, :id
            key :in, :path
            key :description, 'Document identifier returned by POST /v0/cave'
            key :required, true
            key :type, :string
          end

          response 200 do
            key :description, 'Current document status'
            schema do
              key :$ref, :CaveStatusResponse
            end
          end

          response 502 do
            key :description, 'Document processing service unavailable'
            schema do
              key :$ref, :CaveServiceUnavailable
            end
          end
        end
      end

      swagger_path '/v0/cave/{id}/output' do
        operation :get do
          extend Swagger::Responses::AuthenticationError
          extend Swagger::Responses::ForbiddenError

          key :description, 'Retrieve extracted document output for a processed document'
          key :operationId, 'getCaveDocumentOutput'
          key :tags, %w[cave]
          key :produces, ['application/json']

          parameter :authorization

          parameter do
            key :name, :id
            key :in, :path
            key :description, 'Document identifier returned by POST /v0/cave'
            key :required, true
            key :type, :string
          end

          parameter do
            key :name, :type
            key :in, :query
            key :description, "Output variant to request. Defaults to 'artifact' when omitted."
            key :required, false
            key :type, :string
            key :enum, %w[artifact form]
          end

          response 200 do
            key :description, 'Extracted output payload'
            schema do
              key :$ref, :CaveOutputResponse
            end
          end

          response 502 do
            key :description, 'Document processing service unavailable'
            schema do
              key :$ref, :CaveServiceUnavailable
            end
          end
        end
      end

      swagger_path '/v0/cave/{id}/download' do
        operation :get do
          extend Swagger::Responses::AuthenticationError
          extend Swagger::Responses::BadRequestError
          extend Swagger::Responses::ForbiddenError

          key :description, 'Download the JSON payload for a specific extracted key-value pair'
          key :operationId, 'downloadCaveDocumentOutput'
          key :tags, %w[cave]
          key :produces, ['application/json']

          parameter :authorization

          parameter do
            key :name, :id
            key :in, :path
            key :description, 'Document identifier returned by POST /v0/cave'
            key :required, true
            key :type, :string
          end

          parameter do
            key :name, :kvpid
            key :in, :query
            key :description, 'Key-value pair identifier from a prior output response'
            key :required, true
            key :type, :string
          end

          response 200 do
            key :description, 'Stored JSON payload for the requested KVP record'
            schema do
              key :$ref, :CaveKeyValuePayload
            end
          end

          response 502 do
            key :description, 'Document processing service unavailable'
            schema do
              key :$ref, :CaveServiceUnavailable
            end
          end
        end
      end

      swagger_path '/v0/cave/{id}/update' do
        operation :post do
          extend Swagger::Responses::AuthenticationError
          extend Swagger::Responses::BadRequestError
          extend Swagger::Responses::ForbiddenError

          key :description, 'Replace the JSON payload for a specific extracted key-value pair'
          key :operationId, 'updateCaveDocumentOutput'
          key :tags, %w[cave]
          key :consumes, ['application/json']
          key :produces, ['application/json']

          parameter :authorization

          parameter do
            key :name, :id
            key :in, :path
            key :description, 'Document identifier returned by POST /v0/cave'
            key :required, true
            key :type, :string
          end

          parameter do
            key :name, :kvpid
            key :in, :query
            key :description, 'Key-value pair identifier from a prior output response'
            key :required, true
            key :type, :string
          end

          parameter do
            key :name, :payload
            key :in, :body
            key :description, 'Replacement JSON object for the selected KVP record'
            key :required, true
            schema do
              key :$ref, :CaveKeyValuePayload
            end
          end

          response 200 do
            key :description, 'Updated JSON payload'
            schema do
              key :$ref, :CaveKeyValuePayload
            end
          end

          response 502 do
            key :description, 'Document processing service unavailable'
            schema do
              key :$ref, :CaveServiceUnavailable
            end
          end
        end
      end

      swagger_path '/v0/cave/diff' do
        operation :post do
          extend Swagger::Responses::AuthenticationError
          extend Swagger::Responses::BadRequestError

          key :description, 'Compare two JSON objects and return the detected field-level differences'
          key :operationId, 'diffCavePayloads'
          key :tags, %w[cave]
          key :consumes, ['application/json']
          key :produces, ['application/json']

          parameter :authorization

          parameter do
            key :name, :payload
            key :in, :body
            key :description, "JSON object containing both 'lhs' and 'rhs' payloads"
            key :required, true
            schema do
              key :$ref, :CaveDiffRequest
            end
          end

          response 200 do
            key :description, 'Computed differences between the provided payloads'
            schema do
              key :$ref, :CaveDiffResponse
            end
          end
        end
      end
    end
  end
end
