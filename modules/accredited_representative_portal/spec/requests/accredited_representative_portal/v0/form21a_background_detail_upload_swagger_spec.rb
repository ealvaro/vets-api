# frozen_string_literal: true

require 'swagger_helper'
require Rails.root.join('spec', 'rswag_override.rb').to_s
require_relative '../../../rails_helper'

RSpec.describe 'Form 21a Background Detail Upload',
               openapi_spec: 'modules/accredited_representative_portal/app/swagger/v0/swagger.json',
               type: :request do
  let(:representative_user) { create(:representative_user) }

  let!(:in_progress_form) do
    create(
      :in_progress_form,
      form_id: '21a',
      user_uuid: representative_user.uuid,
      form_data: {}.to_json
    )
  end

  before do
    allow(Flipper).to receive(:enabled?)
      .with(:accredited_representative_portal_form_21a)
      .and_return(true)
    login_as(representative_user)
  end

  path '/accredited_representative_portal/v0/form21a/{details_slug}' do
    post('Upload a background detail document') do
      tags 'Form 21a'
      consumes 'multipart/form-data'
      produces 'application/json'
      operationId 'uploadBackgroundDetailDocument'
      description 'Uploads a supporting document for a specific background detail section of Form 21a. ' \
                  'The uploaded file is stored and associated with the in-progress form. ' \
                  'Valid detail slugs correspond to background question sections such as ' \
                  'conviction-details, court-martialed-details, etc.'

      parameter name: :details_slug, in: :path, required: true,
                description: 'The background detail section identifier',
                schema: {
                  type: :string,
                  enum: AccreditedRepresentativePortal::VALID_DETAIL_SLUGS
                }
      parameter name: :file, in: :formData, required: true,
                description: 'The document file to upload (PDF or DOCX)',
                schema: {
                  type: :object,
                  properties: {
                    file: {
                      type: :string,
                      format: :binary,
                      description: 'The document file to upload'
                    }
                  }
                }

      response '200', 'document uploaded successfully' do
        let(:details_slug) { 'conviction-details' }
        let(:file) do
          fixture_file_upload(
            Rails.root.join('modules',
                            'accredited_representative_portal',
                            'spec',
                            'fixtures',
                            'files',
                            '21_686c_empty_form.pdf'),
            'application/pdf'
          )
        end

        schema '$ref' => '#/components/schemas/detailUploadResponse'
        run_test!
      end

      response '400', 'file is missing' do
        let(:details_slug) { 'conviction-details' }
        let(:file) { nil }

        schema '$ref' => '#/components/schemas/missingFileError'
        run_test!
      end

      context 'when file is unprocessable' do
        before do
          allow_any_instance_of(AccreditedRepresentativePortal::Form21aAttachment)
            .to receive(:set_file_data!)
            .and_raise(Common::Exceptions::UnprocessableEntity.new(detail: 'Invalid file type'))
        end

        response '422', 'unprocessable entity - invalid file type or unable to store document' do
          let(:details_slug) { 'conviction-details' }
          let(:file) do
            fixture_file_upload(
              Rails.root.join('modules',
                              'accredited_representative_portal',
                              'spec',
                              'fixtures',
                              'files',
                              'invalid_21a_extension.png'),
              'image/png'
            )
          end

          schema '$ref' => '#/components/schemas/unprocessableEntityError'
          run_test!
        end
      end

      context 'when record is invalid' do
        before do
          allow_any_instance_of(AccreditedRepresentativePortal::Form21aAttachment)
            .to receive(:save!)
            .and_raise(ActiveRecord::RecordInvalid.new(AccreditedRepresentativePortal::Form21aAttachment.new))
        end

        response '422', 'unprocessable entity - invalid file type or unable to store document' do
          let(:details_slug) { 'conviction-details' }
          let(:file) do
            fixture_file_upload(
              Rails.root.join('modules',
                              'accredited_representative_portal',
                              'spec',
                              'fixtures',
                              'files',
                              '21_686c_empty_form.pdf'),
              'application/pdf'
            )
          end

          schema '$ref' => '#/components/schemas/unprocessableEntityError'
          run_test!
        end
      end
    end
  end
end
