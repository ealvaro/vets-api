# frozen_string_literal: true

require 'swagger_helper'
require Rails.root.join('spec', 'rswag_override.rb').to_s
require 'rails_helper'

RSpec.describe 'Form 21P-530a API', openapi_spec: 'config/openapi/openapi.json', type: :request do
  let(:user) { create(:user, :loa1) }

  before do
    host! Settings.hostname
    sign_in_as(user)
    allow(Flipper).to receive(:enabled?).and_call_original
    allow(Flipper).to receive(:enabled?).with(:form_530a_enabled, anything).and_return(true)
    allow(SecureRandom).to receive(:uuid).and_return('12345678-1234-1234-1234-123456789abc')
    allow(Time).to receive(:current).and_return(Time.zone.parse('2025-01-15 10:30:00 UTC'))
  end

  # Shared example for validation failure
  shared_examples 'validates schema and returns 422' do
    it 'returns a 422 when request fails schema validation' do |example|
      submit_request(example.metadata)
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  # Shared example for unauthenticated request
  shared_examples 'returns 401 for unauthenticated request' do |endpoint_description|
    it "returns a 401 for unauthenticated #{endpoint_description}" do |example|
      allow(Flipper).to receive(:enabled?).and_call_original
      allow(Flipper).to receive(:enabled?).with(:aquia_bio_auth_required, anything).and_return(true)
      cookies.delete('api_session')
      submit_request(example.metadata)
      expect(response).to have_http_status(:unauthorized)
    end
  end

  shared_examples 'matches rswag example with status' do |status|
    it "matches rswag example and returns #{status}" do |example|
      submit_request(example.metadata)
      example.metadata[:response][:content] = {
        'application/json' => {
          example: JSON.parse(response.body, symbolize_names: true)
        }
      }
      assert_response_matches_metadata(example.metadata)
      expect(response).to have_http_status(status)
    end
  end

  path '/v0/form21p530a' do
    post 'Submit a 21P-530a form' do
      tags 'benefits_forms'
      operationId 'submitForm21p530a'
      consumes 'application/json'
      produces 'application/json'
      description 'Submit a Form 21P-530a (Application for Burial Allowance - State/Tribal Organizations). ' \
                  'This endpoint requires authentication.'
      security [{ apiKey: [] }]

      parameter name: :form_data, in: :body, required: true, schema: Openapi::Requests::Form21p530a::FORM_SCHEMA

      # Success response
      response '200', 'Form successfully submitted' do
        schema Openapi::Responses::BenefitsIntakeSubmissionResponse::BENEFITS_INTAKE_SUBMISSION_RESPONSE

        let(:form_data) do
          JSON.parse(
            Rails.root.join('spec', 'fixtures', 'form21p530a', 'valid_form.json').read
          ).with_indifferent_access
        end

        include_examples 'matches rswag example with status', :ok
      end

      response '422', 'Unprocessable Entity - schema validation failed' do
        schema '$ref' => '#/components/schemas/Errors'

        let(:form_data) do
          {
            veteranInformation: {
              fullName: { first: 'OnlyFirst' }
            }
          }
        end

        include_examples 'validates schema and returns 422'
      end

      response '401', 'Unauthorized - not authenticated' do
        produces 'application/json'
        schema '$ref' => '#/components/schemas/Errors'

        let(:form_data) do
          JSON.parse(
            Rails.root.join('spec', 'fixtures', 'form21p530a', 'valid_form.json').read
          ).with_indifferent_access
        end

        include_examples 'returns 401 for unauthenticated request', 'form submission'
      end
    end
  end

  path '/v0/form21p530a/download_pdf/{guid}' do
    get 'Download PDF for Form 21P-530a by GUID' do
      tags 'benefits_forms'
      operationId 'downloadForm21p530aPdfByGuid'
      produces 'application/pdf'
      description 'Download a filled PDF for Form 21P-530a using a previously-saved claim GUID.'
      security [{ apiKey: [] }]

      parameter name: :guid, in: :path, type: :string, required: true,
                description: 'Saved claim GUID for Form 21P-530a'

      response '200', 'PDF generated successfully' do
        produces 'application/pdf'
        schema type: :string, format: :binary

        let(:form_data) do
          JSON.parse(
            Rails.root.join('spec', 'fixtures', 'form21p530a', 'valid_form.json').read
          ).with_indifferent_access
        end
        let(:claim) do
          SavedClaim::Form21p530a.create!(
            form: form_data.to_json,
            form_id: '21P-530A',
            user_account: user.user_account
          )
        end
        let(:guid) { claim.guid }
        let(:temp_file_path) { '/tmp/test_form21p530a.pdf' }

        it 'returns a PDF file for a saved claim GUID' do |example|
          allow_any_instance_of(SavedClaim::Form21p530a).to receive(:to_pdf).and_return(temp_file_path)
          allow(File).to receive(:read).and_call_original
          allow(File).to receive(:read).with(temp_file_path).and_return('PDF_BINARY_CONTENT')
          allow(File).to receive(:exist?).and_call_original
          allow(File).to receive(:exist?).with(temp_file_path).and_return(true)
          allow(File).to receive(:delete).with(temp_file_path)

          submit_request(example.metadata)
          expect(claim.guid).to eq(guid)
          expect(response).to have_http_status(:ok)
          expect(response.content_type).to eq('application/pdf')
          expect(response.headers['Content-Disposition']).to include('attachment')
          expect(response.headers['Content-Disposition']).to include('.pdf')
        end
      end

      response '404', 'Not Found - claim GUID not found' do
        produces 'application/json'
        schema '$ref' => '#/components/schemas/Errors'

        let(:guid) { SecureRandom.uuid }

        it 'returns a 404 for an unknown GUID' do |example|
          submit_request(example.metadata)
          expect(response).to have_http_status(:not_found)
        end
      end

      response '500', 'Internal Server Error - PDF generation failed' do
        produces 'application/json'
        schema '$ref' => '#/components/schemas/Errors'

        let(:form_data) do
          JSON.parse(
            Rails.root.join('spec', 'fixtures', 'form21p530a', 'valid_form.json').read
          ).with_indifferent_access
        end
        let(:claim) do
          SavedClaim::Form21p530a.create!(
            form: form_data.to_json,
            form_id: '21P-530A',
            user_account: user.user_account
          )
        end
        let(:guid) { claim.guid }

        it 'returns a 500 when PDF generation fails for GUID download' do |example|
          allow_any_instance_of(SavedClaim::Form21p530a)
            .to receive(:to_pdf)
            .and_raise(StandardError, 'PDF generation error')

          submit_request(example.metadata)
          expect(response).to have_http_status(:internal_server_error)
        end
      end

      response '401', 'Unauthorized - not authenticated' do
        produces 'application/json'
        schema '$ref' => '#/components/schemas/Errors'

        let(:form_data) do
          JSON.parse(
            Rails.root.join('spec', 'fixtures', 'form21p530a', 'valid_form.json').read
          ).with_indifferent_access
        end
        let(:claim) do
          SavedClaim::Form21p530a.create!(
            form: form_data.to_json,
            form_id: '21P-530A',
            user_account: user.user_account
          )
        end
        let(:guid) { claim.guid }

        include_examples 'returns 401 for unauthenticated request', 'PDF download by GUID'
      end
    end
  end
end
