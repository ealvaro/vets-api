# frozen_string_literal: true

require_relative '../../../rails_helper'

RSpec.describe 'AccreditedRepresentativePortal::V0::Form21a', type: :request do
  subject(:make_post_request) { post('/accredited_representative_portal/v0/form21a', params: payload, headers:) }

  let(:form_data) do
    {
      'firstName' => 'John',
      'lastName' => 'Doe',
      'homePhone' => '555-555-1234',
      'homeEmail' => 'john.doe@example.com',
      'applicationStatusId' => 1,
      'accreditationTypeId' => 2,
      'genderId' => 1,
      'instructionAcknowledge' => true,
      'employmentStatusId' => 3,
      'icnNo' => representative_user.icn,
      'uId' => representative_user.uuid
    }
  end

  let(:json) { form_data.to_json }
  let(:payload) do
    {
      form21aSubmission: {
        form: json
      }
    }.to_json
  end

  let(:mock_schema) do
    {
      '$schema' => 'http://json-schema.org/draft-04/schema#',
      'title' => 'Apply to become a VA-accredited attorney or claims agent',
      'type' => 'object',
      'properties' => { 'firstName' => { 'type' => 'string' } },
      'required' => ['firstName'],
      'additionalProperties' => false
    }
  end

  let(:representative_user) { create(:representative_user) }
  let(:headers) { { 'Content-Type' => 'application/json' } }

  def expected_resubmittable_response(errors)
    {
      'errors' => errors,
      'formSubmission' => {
        'status' => 'resubmittable',
        'message' => 'We saved your application. Please try submitting Form 21a again.'
      }
    }
  end

  before do
    login_as(representative_user)
  end

  describe 'POST /accredited_representative_portal/v0/form21a' do
    context 'when the user is not LOA3' do
      let(:non_loa3_user) { create(:representative_user) }

      before do
        allow(Flipper).to receive(:enabled?)
          .with(:accredited_representative_portal_form_21a)
          .and_return(true)

        allow_any_instance_of(AccreditedRepresentativePortal::V0::Form21aController)
          .to receive(:current_user)
          .and_return(non_loa3_user)

        allow(non_loa3_user).to receive(:loa).and_return({ current: 1, highest: 1 })

        login_as(non_loa3_user)
      end

      it 'returns 404 and does not call the service' do
        expect(AccreditationService).not_to receive(:submit_form21a)
        make_post_request
        expect(response).to have_http_status(:not_found)
      end
    end

    context 'with valid JSON' do
      let!(:in_progress_form) { create(:in_progress_form, form_id: '21a', user_uuid: representative_user.uuid) }

      it 'logs success and destroys in-progress form' do
        get('/accredited_representative_portal/v0/in_progress_forms/21a')
        expect(response).to have_http_status(:ok)
        expect(parsed_response.keys).to contain_exactly('formData', 'metadata')

        allow(AccreditationService).to receive(:submit_form21a) do |form_array, _uuid|
          form = form_array.first
          expect(form['icnNo']).to eq(representative_user.icn)
          expect(form['uId']).to eq(representative_user.uuid)
          instance_double(
            Faraday::Response,
            success?: true,
            body: {
              'uploaded' => [
                {
                  'application' => {
                    'id' => '12345'
                  }
                }
              ],
              'result' => 'success'
            },
            status: 201
          )
        end

        expect(Rails.logger).to receive(:info).with(
          a_string_including(
            'Form21aController: Form 21a successfully submitted to OGC service by user with' \
            " user_uuid=#{representative_user.uuid}"
          )
        )

        make_post_request
        expect(response).to have_http_status(:created)
        expect(parsed_response).to eq(
          'uploaded' => [
            {
              'application' => {
                'id' => '12345'
              }
            }
          ],
          'result' => 'success'
        )

        get('/accredited_representative_portal/v0/in_progress_forms/21a')
        expect(response).to have_http_status(:ok)
        expect(parsed_response).to eq({})
      end
    end

    context 'when response includes uploaded application id and form has document uploads' do
      let(:in_progress_form_data) do
        {
          'convictionDetailsDocuments' => [
            {
              'name' => 'test_doc.pdf',
              'confirmationCode' => 'guid-123',
              'size' => 12_345,
              'type' => 'application/pdf'
            }
          ]
        }.to_json
      end

      let!(:in_progress_form) do
        create(
          :in_progress_form,
          form_id: '21a',
          user_uuid: representative_user.uuid,
          form_data: in_progress_form_data
        )
      end

      before do
        allow(Flipper).to receive(:enabled?)
          .with(:accredited_representative_portal_form_21a)
          .and_return(true)
      end

      it 'enqueues document upload jobs when application id is present' do
        allow(AccreditationService).to receive(:submit_form21a).and_return(
          instance_double(
            Faraday::Response,
            success?: true,
            body: {
              'uploaded' => [
                {
                  'application' => {
                    'id' => '12345'
                  }
                }
              ],
              'result' => 'success'
            },
            status: 201
          )
        )

        expect(AccreditedRepresentativePortal::Form21aDocumentUploadService)
          .to receive(:enqueue_uploads)
          .with(in_progress_form:, application_id: '12345')
          .and_return(1)

        make_post_request

        expect(response).to have_http_status(:created)
      end

      it 'destroys in-progress form after enqueuing uploads' do
        allow(AccreditationService).to receive(:submit_form21a).and_return(
          instance_double(
            Faraday::Response,
            success?: true,
            body: {
              'uploaded' => [
                {
                  'application' => {
                    'id' => '12345'
                  }
                }
              ],
              'result' => 'success'
            },
            status: 201
          )
        )

        allow(AccreditedRepresentativePortal::Form21aDocumentUploadService)
          .to receive(:enqueue_uploads)
          .and_return(1)

        expect { make_post_request }.to change(InProgressForm, :count).by(-1)
      end

      it 'still returns success and destroys in-progress form when application id is missing' do
        allow(AccreditationService).to receive(:submit_form21a).and_return(
          instance_double(
            Faraday::Response,
            success?: true,
            body: {
              'uploaded' => [
                {
                  'application' => {}
                }
              ],
              'result' => 'success'
            },
            status: 201
          )
        )

        expect(AccreditedRepresentativePortal::Form21aDocumentUploadService)
          .not_to receive(:enqueue_uploads)

        allow(Rails.logger).to receive(:error).and_call_original
        allow(Rails.logger).to receive(:info).and_call_original

        expect { make_post_request }.to change(InProgressForm, :count).by(-1)

        expect(response).to have_http_status(:created)
        expect(parsed_response).to eq(
          'uploaded' => [
            {
              'application' => {}
            }
          ],
          'result' => 'success'
        )

        expect(Rails.logger).to have_received(:error).with(
          a_string_including('Missing application id in GCLAWS response')
        )
      end
    end

    context 'when response includes application id but no in-progress form exists' do
      before do
        allow(Flipper).to receive(:enabled?)
          .with(:accredited_representative_portal_form_21a)
          .and_return(true)

        InProgressForm.where(form_id: '21a', user_uuid: representative_user.uuid).delete_all
      end

      it 'logs a warning, skips document upload enqueueing, and still renders the successful response' do
        allow(AccreditationService).to receive(:submit_form21a).and_return(
          instance_double(
            Faraday::Response,
            success?: true,
            body: {
              'uploaded' => [
                {
                  'application' => {
                    'id' => '12345'
                  }
                }
              ],
              'result' => 'success'
            },
            status: 201
          )
        )

        expect(AccreditedRepresentativePortal::Form21aDocumentUploadService)
          .not_to receive(:enqueue_uploads)

        allow(Rails.logger).to receive(:warn).and_call_original
        allow(Rails.logger).to receive(:info).and_call_original

        make_post_request

        expect(response).to have_http_status(:created)
        expect(parsed_response).to eq(
          'uploaded' => [
            {
              'application' => {
                'id' => '12345'
              }
            }
          ],
          'result' => 'success'
        )

        expect(Rails.logger).to have_received(:warn).with(
          a_string_including('No in-progress form found after successful Form 21a submission')
        )
      end
    end

    context 'when in-progress form cleanup fails after document uploads are enqueued' do
      let!(:in_progress_form) { create(:in_progress_form, form_id: '21a', user_uuid: representative_user.uuid) }

      before do
        allow(Flipper).to receive(:enabled?)
          .with(:accredited_representative_portal_form_21a)
          .and_return(true)
      end

      it 'logs the cleanup error and still renders the successful OGC response' do
        allow(AccreditationService).to receive(:submit_form21a).and_return(
          instance_double(
            Faraday::Response,
            success?: true,
            body: {
              'uploaded' => [
                {
                  'application' => {
                    'id' => '12345'
                  }
                }
              ],
              'result' => 'success'
            },
            status: 201
          )
        )

        allow(AccreditedRepresentativePortal::Form21aDocumentUploadService)
          .to receive(:enqueue_uploads)
          .and_return(0)

        allow_any_instance_of(InProgressForm)
          .to receive(:destroy!)
          .and_raise(ActiveRecord::ActiveRecordError, 'cleanup failed')

        allow(Rails.logger).to receive(:error).and_call_original
        allow(Rails.logger).to receive(:info).and_call_original

        make_post_request

        expect(response).to have_http_status(:created)
        expect(parsed_response).to eq(
          'uploaded' => [
            {
              'application' => {
                'id' => '12345'
              }
            }
          ],
          'result' => 'success'
        )

        expect(Rails.logger).to have_received(:error).with(
          a_string_including('Failed to destroy in-progress form after successful Form 21a submission')
        )
      end
    end

    context 'with invalid JSON' do
      let(:payload) { 'invalid_json' }

      it 'logs and returns a bad request' do
        expect(Rails.logger).to receive(:error).with(
          a_string_including(
            'Form21aController: Invalid JSON in request body for user with' \
            " user_uuid=#{representative_user.uuid}."
          )
        )

        make_post_request
        expect(response).to have_http_status(:bad_request)
        expect(parsed_response['errors']).to include('Invalid JSON')
      end
    end

    context 'when form does not match schema' do
      let(:form_data) { { 'firstName' => 1234 } }

      before do
        allow(VetsJsonSchema::SCHEMAS).to receive(:[]).with('21A').and_return(mock_schema)
      end

      it 'logs and returns a bad request' do
        expect(Rails.logger).to receive(:error).with(
          a_string_including(
            "Form21aController: Invalid JSON in request body for user with user_uuid=#{representative_user.uuid}"
          )
        )

        make_post_request
        expect(response).to have_http_status(:bad_request)
        expect(parsed_response['errors']).to match(/firstName.*type/)
        expect(parsed_response['errors']).to match(/icnNo|uId/)
      end
    end

    context 'when service returns a blank response' do
      let!(:in_progress_form) { create(:in_progress_form, form_id: '21a', user_uuid: representative_user.uuid) }

      it 'logs, returns resubmittable messaging, and retains the in-progress form' do
        allow(AccreditationService).to receive(:submit_form21a).and_return(
          instance_double(Faraday::Response, success?: false, body: nil, status: 204)
        )

        expect(AccreditedRepresentativePortal::Form21aDocumentUploadService)
          .not_to receive(:enqueue_uploads)

        expect(Rails.logger).to receive(:error).with(
          a_string_including(
            'Form21aController: Blank or unparsable response from external OGC service'
          )
        )

        expect { make_post_request }.not_to change(InProgressForm, :count)

        expect(response).to have_http_status(:service_unavailable)
        expect(parsed_response).to eq(
          expected_resubmittable_response('Blank or unparsable response from external OGC service')
        )
        expect(InProgressForm.form_for_user('21a', representative_user)).to be_present
      end
    end

    context 'when service returns a 400 with validation errors' do
      let(:error_body) do
        {
          'errors' => {
            '[0].education[0].InstitutionTypeId' => [
              'The InstitutionTypeId field is required.'
            ]
          },
          'type' => 'https://tools.ietf.org/html/rfc9110#section-15.5.1',
          'title' => 'One or more validation errors occurred.',
          'status' => 400,
          'traceId' => '00-685b4dee0000000030e6cefe3c3fd8ff-25aa3dda711bee62-01'
        }
      end

      before do
        allow(AccreditationService).to receive(:submit_form21a).and_return(
          instance_double(Faraday::Response, success?: false, status: 400, body: error_body)
        )
      end

      it 'logs, returns resubmittable messaging, and retains the in-progress form' do
        create(:in_progress_form, form_id: '21a', user_uuid: representative_user.uuid)

        expect(AccreditedRepresentativePortal::Form21aDocumentUploadService)
          .not_to receive(:enqueue_uploads)

        expect(Rails.logger).to receive(:error).with(
          a_string_including('OGC service returned error response (status=400)')
        )

        expect { make_post_request }.not_to change(InProgressForm, :count)

        expect(response).to have_http_status(:bad_request)
        expect(parsed_response).to eq(expected_resubmittable_response(error_body))
        expect(InProgressForm.form_for_user('21a', representative_user)).to be_present
      end
    end

    context 'when service returns a 503' do
      let(:error_body) { { 'errors' => { 'service' => ['Temporarily unavailable'] }, 'status' => 503 } }

      before do
        allow(AccreditationService).to receive(:submit_form21a).and_return(
          instance_double(Faraday::Response, success?: false, status: 503, body: error_body)
        )
      end

      it 'logs, returns resubmittable messaging, and retains the in-progress form' do
        create(:in_progress_form, form_id: '21a', user_uuid: representative_user.uuid)

        expect(AccreditedRepresentativePortal::Form21aDocumentUploadService)
          .not_to receive(:enqueue_uploads)

        expect(Rails.logger).to receive(:error).with(
          a_string_including('OGC service returned error response (status=503)')
        )

        expect { make_post_request }.not_to change(InProgressForm, :count)

        expect(response).to have_http_status(:service_unavailable)
        expect(parsed_response).to eq(expected_resubmittable_response(error_body))
        expect(InProgressForm.form_for_user('21a', representative_user)).to be_present
      end
    end

    context 'when an unexpected error occurs' do
      it 'logs and returns an internal server error' do
        allow_any_instance_of(AccreditedRepresentativePortal::V0::Form21aController)
          .to receive(:parse_request_body).and_raise(StandardError, 'Unexpected error')

        allow(Rails.logger).to receive(:error).and_call_original

        make_post_request

        expect(Rails.logger).to have_received(:error).with(
          a_string_including("ARP: Unexpected error occurred for user with user_uuid=#{representative_user.uuid}")
        )

        expect(response).to have_http_status(:internal_server_error)
        expect(parsed_response).to match(
          'errors' => [
            hash_including(
              'title' => 'Internal server error',
              'detail' => 'Internal server error',
              'code' => '500',
              'status' => '500'
            )
          ]
        )
      end
    end

    context 'when a network error occurs' do
      let!(:in_progress_form) { create(:in_progress_form, form_id: '21a', user_uuid: representative_user.uuid) }

      it 'logs, returns resubmittable messaging, and retains the in-progress form' do
        allow(AccreditationService).to receive(:submit_form21a).and_raise(Faraday::TimeoutError.new('timeout'))

        expect(AccreditedRepresentativePortal::Form21aDocumentUploadService)
          .not_to receive(:enqueue_uploads)

        expect(Rails.logger).to receive(:error).with(
          a_string_including('Form21aController: Network error: Faraday::TimeoutError')
        )

        expect { make_post_request }.not_to change(InProgressForm, :count)

        expect(response).to have_http_status(:service_unavailable)
        expect(parsed_response).to eq(expected_resubmittable_response('Service temporarily unavailable'))
        expect(InProgressForm.form_for_user('21a', representative_user)).to be_present
      end
    end

    context 'when an unexpected error occurs in service call' do
      it 'logs the error and returns a 500' do
        allow(AccreditationService).to receive(:submit_form21a).and_raise(StandardError.new('boom'))

        expect(Rails.logger).to receive(:error).with(
          a_string_including('Form21aController: Unexpected error: StandardError')
        )

        make_post_request
        expect(response).to have_http_status(:internal_server_error)
        expect(parsed_response).to eq('errors' => 'Internal server error')
      end
    end

    context 'when form21aSubmission key is missing or nil' do
      let(:payload) { {}.to_json }

      it 'logs and returns a bad request' do
        expect(Rails.logger).to receive(:error).with(
          a_string_including(
            "Form21aController: Invalid JSON in request body for user with user_uuid=#{representative_user.uuid}"
          )
        )

        make_post_request
        expect(response).to have_http_status(:bad_request)
        expect(parsed_response['errors']).to include('Invalid JSON')
      end
    end

    context 'when the Form 21a feature flag is disabled' do
      before do
        allow(Flipper).to receive(:enabled?)
          .with(:accredited_representative_portal_form_21a)
          .and_return(false)
      end

      it 'returns 404 Not Found (routing error)' do
        make_post_request
        expect(response).to have_http_status(:not_found)
      end
    end

    context 'when nested form JSON is invalid' do
      let(:payload) do
        {
          form21aSubmission: {
            form: 'not-json' # will raise JSON::ParserError inside parse_request_body
          }
        }.to_json
      end

      it 'logs and returns a bad request for invalid nested JSON' do
        expect(Rails.logger).to receive(:error).with(
          a_string_including(
            "Form21aController: Invalid JSON in request body for user with user_uuid=#{representative_user.uuid}"
          )
        )

        make_post_request
        expect(response).to have_http_status(:bad_request)
        expect(parsed_response['errors']).to include('Invalid JSON')
      end
    end

    context 'when a connection error occurs' do
      let!(:in_progress_form) { create(:in_progress_form, form_id: '21a', user_uuid: representative_user.uuid) }

      it 'logs, returns resubmittable messaging, and retains the in-progress form' do
        allow(AccreditationService).to receive(:submit_form21a)
          .and_raise(Faraday::ConnectionFailed.new('connection down'))

        expect(AccreditedRepresentativePortal::Form21aDocumentUploadService)
          .not_to receive(:enqueue_uploads)

        expect(Rails.logger).to receive(:error).with(
          a_string_including('Form21aController: Network error: Faraday::ConnectionFailed')
        )

        expect { make_post_request }.not_to change(InProgressForm, :count)

        expect(response).to have_http_status(:service_unavailable)
        expect(parsed_response).to eq(expected_resubmittable_response('Service temporarily unavailable'))
        expect(InProgressForm.form_for_user('21a', representative_user)).to be_present
      end
    end
  end

  describe 'POST /accredited_representative_portal/v0/form21a/:details_slug' do
    subject(:make_post_request) do
      post(path, params: { file: }, headers:)
    end

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

    let(:slug) { 'conviction-details' }
    let(:path) { "/accredited_representative_portal/v0/form21a/#{slug}" }

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

    context 'when the user is not LOA3' do
      let(:non_loa3_user) { create(:representative_user) }
      let(:slug) { 'conviction-details' }
      let(:path) { "/accredited_representative_portal/v0/form21a/#{slug}" }
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

      before do
        allow(Flipper).to receive(:enabled?)
          .with(:accredited_representative_portal_form_21a)
          .and_return(true)

        allow_any_instance_of(AccreditedRepresentativePortal::RepresentativeUser)
          .to receive(:loa)
          .and_return({ current: 1, highest: 1 })

        login_as(non_loa3_user)
      end

      it 'returns 404 and does not process the file' do
        expect(Rails.logger).not_to receive(:info).with(
          a_string_including('Form21aController: Received details upload')
        )

        expect { post(path, params: { file: }, headers:) }
          .not_to change(AccreditedRepresentativePortal::Form21aAttachment, :count)

        expect(response).to have_http_status(:not_found)
        expect(parsed_response).to match(
          'errors' => [
            hash_including(
              'title' => 'Not found',
              'status' => '404'
            )
          ]
        )
      end
    end

    context 'when file upload is unprocessable' do
      before do
        allow_any_instance_of(AccreditedRepresentativePortal::Form21aAttachment)
          .to receive(:set_file_data!)
          .and_raise(Common::Exceptions::UnprocessableEntity.new(detail: 'Invalid file type'))
      end

      it 'returns unprocessable entity with error message' do
        make_post_request

        expect(response).to have_http_status(:unprocessable_entity)
        expect(parsed_response['errors']).to include('Invalid file type')
      end
    end

    context 'when attachment fails validation' do
      before do
        allow_any_instance_of(AccreditedRepresentativePortal::Form21aAttachment)
          .to receive(:save!)
          .and_raise(ActiveRecord::RecordInvalid.new(
                       AccreditedRepresentativePortal::Form21aAttachment.new
                     ))
      end

      it 'returns unprocessable entity with generic error message' do
        make_post_request

        expect(response).to have_http_status(:unprocessable_entity)
        expect(parsed_response['errors']).to eq('Unable to store document')
      end
    end

    context 'when file upload fails integrity checks' do
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

      it 'returns unprocessable entity with error message' do
        make_post_request

        expect(response).to have_http_status(:unprocessable_entity)
        expect(parsed_response['errors']).to be_present
      end
    end

    context 'with a valid slug and file' do
      it 'creates an attachment, updates the in-progress form, and returns confirmation data' do
        allow(Rails.logger).to receive(:info).and_call_original

        expect do
          make_post_request
        end.to change(AccreditedRepresentativePortal::Form21aAttachment, :count).by(1)

        expect(Rails.logger).to have_received(:info).with(
          a_string_including(
            "Form21aController: Received details upload for slug=#{slug} user_uuid=#{representative_user.uuid}"
          )
        )

        expect(response).to have_http_status(:ok)

        attrs = parsed_response.fetch('data').fetch('attributes')
        expect(attrs['confirmationCode']).to be_present
        expect(attrs['name']).to eq('21_686c_empty_form.pdf')
        expect(attrs['size']).to eq(file.size)
        expect(attrs['type']).to eq('application/pdf')
        expect(attrs['errorMessage']).to eq('')

        in_progress_form.reload
        form_data = JSON.parse(in_progress_form.form_data)

        documents = form_data['convictionDetailsDocuments']
        expect(documents).to be_an(Array)
        expect(documents.size).to eq(1)

        document = documents.first
        expect(document['name']).to eq('21_686c_empty_form.pdf')
        expect(document['size']).to eq(file.size)
        expect(document['type']).to eq('application/pdf')
        expect(document['confirmationCode']).to eq(attrs['confirmationCode'])
      end
    end

    context 'when file is missing' do
      subject(:make_post_request) { post(path, params: {}, headers:) }

      it 'returns a bad request with an error message' do
        make_post_request

        expect(response).to have_http_status(:bad_request)
        expect(parsed_response).to eq('errors' => 'file is required')
      end
    end

    context 'with an invalid slug' do
      let(:slug) { 'not-a-real-slug' }
      let(:path) { "/accredited_representative_portal/v0/form21a/#{slug}" }

      it 'returns 404 due to routing constraint' do
        make_post_request
        expect(response).to have_http_status(:not_found)
      end
    end

    context 'when the feature flag is disabled' do
      before do
        allow(Flipper).to receive(:enabled?)
          .with(:accredited_representative_portal_form_21a)
          .and_return(false)
      end

      it 'returns 404' do
        make_post_request
        expect(response).to have_http_status(:not_found)
      end
    end

    context 'when there is no in-progress form for the user' do
      let!(:in_progress_form) { nil }

      before do
        InProgressForm.where(form_id: '21a', user_uuid: representative_user.uuid).delete_all
      end

      it 'returns 404 via routing_error' do
        make_post_request
        expect(response).to have_http_status(:not_found)
      end
    end
  end
end
