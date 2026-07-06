# frozen_string_literal: true

class AccreditedRepresentativePortal::RswagConfig
  def config
    {
      'modules/accredited_representative_portal/app/swagger/v0/swagger.json' => {
        openapi: '3.0.1',
        info:,
        tags:,
        components: {
          schemas:
        },
        paths: {},
        servers: [localhost, sandbox, staging, production]
      }
    }
  end

  def info
    {
      title: 'Accredited Representative Portal API',
      version: '0.1.0',
      termsOfService: 'https://developer.va.gov/terms-of-service',
      description: 'APIs powering the Accredited Representative Portal, including Form 21a submission ' \
                   'and background detail document uploads.'
    }
  end

  def tags
    [
      {
        name: 'Form 21a',
        description: 'Form 21a submission and background detail document uploads'
      }
    ]
  end

  def schemas
    {
      detailUploadResponse: detail_upload_response,
      missingFileError: missing_file_error,
      unprocessableEntityError: unprocessable_entity_error
    }
  end

  def missing_file_error
    {
      type: :object,
      properties: {
        errors: {
          type: :string,
          example: 'file is required'
        }
      }
    }
  end

  def unprocessable_entity_error
    {
      type: :object,
      properties: {
        errors: {
          type: :string,
          example: 'Invalid file type'
        }
      }
    }
  end

  def detail_upload_response
    {
      type: :object,
      properties: {
        data: {
          type: :object,
          properties: {
            attributes: {
              type: :object,
              properties: {
                errorMessage: { type: :string, example: '' },
                confirmationCode: { type: :string, example: 'a1b2c3d4-e5f6-7890-abcd-ef1234567890' },
                name: { type: :string, example: 'document.pdf' },
                size: { type: :integer, example: 12_345 },
                type: { type: :string, example: 'application/pdf' }
              }
            }
          }
        }
      }
    }
  end

  private

  def localhost
    {
      url: 'https://localhost:3000',
      description: 'Local'
    }
  end

  def sandbox
    {
      url: 'https://dev-api.va.gov',
      description: 'Sandbox'
    }
  end

  def staging
    {
      url: 'https://staging-api.va.gov',
      description: 'Staging'
    }
  end

  def production
    {
      url: 'https://api.va.gov',
      description: 'Production'
    }
  end
end
