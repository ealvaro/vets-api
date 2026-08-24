# frozen_string_literal: true

require 'rails_helper'
require 'lgy/service'

Rspec.describe 'V0::Coe', type: :request do
  context 'when user is signed in' do
    let(:user) { create(:evss_user, :loa3, icn: '123498767V234859') }

    before { sign_in_as user }

    describe 'GET v0/coe/status' do
      context 'when the user is authorized' do
        it 'allows the request to reach the action' do
          service_instance = instance_double(LGY::Service, coe_status: { status: 'ELIGIBLE' })
          allow(LGY::Service).to receive(:new).and_return(service_instance)

          get '/v0/coe/status'

          expect(response).to have_http_status(:ok)
          expect(LGY::Service).to have_received(:new)
        end
      end

      context 'when the user is not authorized because not loa3' do
        let(:user) { create(:evss_user, :loa1, icn: '123498767V234859') }

        it 'returns forbidden without calling the action' do
          expect(LGY::Service).not_to receive(:new)

          get '/v0/coe/status'

          expect(response).to have_http_status(:forbidden)
        end
      end

      context 'when the user is not authorized because missing icn' do
        let(:user) { build(:evss_user, :loa3, icn: nil) }

        it 'returns forbidden without calling the action' do
          expect(LGY::Service).not_to receive(:new)

          get '/v0/coe/status'

          expect(response).to have_http_status(:forbidden)
        end
      end

      context 'when the user is not authorized because missing edipi' do
        let(:user) { build(:evss_user, :loa3, edipi: nil) }

        it 'returns forbidden without calling the action' do
          expect(LGY::Service).not_to receive(:new)

          get '/v0/coe/status'

          expect(response).to have_http_status(:forbidden)
        end
      end

      context 'when determination is eligible and application is 404' do
        it 'response code is 200' do
          VCR.use_cassette 'lgy/determination_eligible' do
            VCR.use_cassette 'lgy/application_not_found' do
              get '/v0/coe/status'
              expect(response).to have_http_status(:ok)
            end
          end
        end

        it 'logs success and increments StatsD metric' do
          expected_coe_status = { status: 'ELIGIBLE', reference_number: 'ABC123' }
          service_instance = instance_double(LGY::Service, coe_status: expected_coe_status)
          allow(LGY::Service).to receive(:new).and_return(service_instance)

          expect(Rails.logger).to receive(:info).with(
            'COE status retrieved successfully',
            hash_including(user_uuid: user.uuid, status: 'ELIGIBLE')
          )
          allow(StatsD).to receive(:increment).and_call_original
          expect(StatsD).to receive(:increment).with('api.lgy_coe.status.success')

          get '/v0/coe/status'
        end

        it 'response is in JSON format' do
          VCR.use_cassette 'lgy/determination_eligible' do
            VCR.use_cassette 'lgy/application_not_found' do
              get '/v0/coe/status'
              expect(response.content_type).to eq('application/json; charset=utf-8')
            end
          end
        end

        it 'response status key is ELIGIBLE' do
          VCR.use_cassette 'lgy/determination_eligible' do
            VCR.use_cassette 'lgy/application_not_found' do
              get '/v0/coe/status'
              json_body = JSON.parse(response.body)
              expect(json_body['data']['attributes']).to include 'status' => 'ELIGIBLE'
            end
          end
        end
      end

      context 'when an error occurs' do
        it 'logs error and increments failure metric' do
          allow_any_instance_of(LGY::Service).to receive(:coe_status).and_raise(StandardError, 'Test error')

          allow(Rails.logger).to receive(:error).with(any_args).and_call_original
          expect(Rails.logger).to receive(:error).with(
            'COE status request failed',
            hash_including(user_uuid: user.uuid, error: 'Test error')
          ).and_call_original
          allow(StatsD).to receive(:increment).and_call_original
          expect(StatsD).to receive(:increment).with('api.lgy_coe.status.failure')

          get '/v0/coe/status'
          expect(response).to have_http_status(:internal_server_error)
        end
      end
    end

    describe 'GET v0/coe/download_coe' do
      context 'when COE file exists' do
        before do
          @lgy_service = double('LGY Service')
          # Simulate http response object
          @res = OpenStruct.new(body: File.read('spec/fixtures/files/lgy_file.pdf'))
          allow(@lgy_service).to receive(:get_coe_file).and_return @res
          allow_any_instance_of(V0::CoeController).to receive(:lgy_service) { @lgy_service }
        end

        it 'response code is 200' do
          get '/v0/coe/download_coe'
          expect(response).to have_http_status(:ok)
        end

        it 'increments success StatsD metric' do
          allow(StatsD).to receive(:increment).and_call_original
          expect(StatsD).to receive(:increment).with('api.lgy_coe.download_coe.success')

          get '/v0/coe/download_coe'
        end

        it 'response is in PDF format' do
          get '/v0/coe/download_coe'
          expect(response.content_type).to eq('application/pdf')
        end

        it 'response body is correct' do
          get '/v0/coe/download_coe'
          expect(response.body).to eq @res.body
        end
      end

      context 'when an error occurs' do
        it 'logs error and increments failure metric' do
          allow_any_instance_of(LGY::Service).to receive(:get_coe_file).and_raise(StandardError, 'Download failed')

          allow(Rails.logger).to receive(:error).with(any_args).and_call_original
          expect(Rails.logger).to receive(:error).with(
            'COE file download failed',
            hash_including(user_uuid: user.uuid, error: 'Download failed')
          ).and_call_original
          allow(StatsD).to receive(:increment).and_call_original
          expect(StatsD).to receive(:increment).with('api.lgy_coe.download_coe.failure')

          get '/v0/coe/download_coe'
          expect(response).to have_http_status(:internal_server_error)
        end
      end
    end

    describe 'POST v0/coe/submit_coe_claim' do
      context 'when claim validation fails' do
        it 'logs validation errors without PII and increments failure metric' do
          claim = build(:coe_claim)
          validation_errors = ActiveModel::Errors.new(claim)

          allow(SavedClaim::CoeClaim).to receive(:new).and_return(claim)
          allow(claim).to receive_messages(save: false, errors: validation_errors)
          validation_errors.add(:first_name, 'is required')

          # Allow other Rails error logging to avoid conflicts
          allow(Rails.logger).to receive(:error).with(any_args).and_call_original
          expect(Rails.logger).to receive(:error).with(
            'COE claim save failed',
            hash_including(
              user_uuid: user.uuid,
              validation_error_count: 1,
              failed_attributes: %i[first_name]
            )
          ).and_call_original

          allow(StatsD).to receive(:increment).and_call_original
          expect(StatsD).to receive(:increment).with('api.lgy_coe.submit_coe_claim.failure')

          post '/v0/coe/submit_coe_claim', params: { lgy_coe_claim: { form: '{}' } }
          expect(response).to have_http_status(:unprocessable_entity)
        end
      end

      context 'when claim submission succeeds' do
        it 'logs success with claim details and increments success metric' do
          claim = double('claim',
                         save: true,
                         confirmation_number: 'COE123456',
                         form_id: 'test-form-id',
                         class: SavedClaim::CoeClaim)
          allow(claim).to receive(:send_to_lgy).with(edipi: user.edipi, icn: user.icn).and_return('REF789')
          allow(SavedClaim::CoeClaim).to receive(:new).and_return(claim)
          allow(InProgressForm).to receive(:form_for_user).and_return(nil)

          expect(Rails.logger).to receive(:info).with(
            'COE claim submitted successfully',
            hash_including(
              user_uuid: user.uuid,
              claim_id: 'COE123456',
              form: '26-1880',
              reference_number: 'REF789'
            )
          )
          allow(StatsD).to receive(:increment).and_call_original
          expect(StatsD).to receive(:increment).with('api.lgy_coe.submit_coe_claim.success')

          post '/v0/coe/submit_coe_claim', params: { lgy_coe_claim: { form: '{}' } }
          expect(response).to have_http_status(:ok)
        end
      end

      context 'when LGY service fails' do
        it 'logs error and increments failure metric' do
          claim = double('claim', save: true, send_to_lgy: nil)
          allow(SavedClaim::CoeClaim).to receive(:new).and_return(claim)
          allow(claim).to receive(:send_to_lgy).and_raise(StandardError, 'LGY service error')

          allow(Rails.logger).to receive(:error).with(any_args).and_call_original
          expect(Rails.logger).to receive(:error).with(
            'COE claim submission failed',
            hash_including(user_uuid: user.uuid, error: 'LGY service error')
          ).and_call_original
          allow(StatsD).to receive(:increment).and_call_original
          expect(StatsD).to receive(:increment).with('api.lgy_coe.submit_coe_claim.failure')

          post '/v0/coe/submit_coe_claim', params: { lgy_coe_claim: { form: '{}' } }
          expect(response).to have_http_status(:internal_server_error)
        end
      end
    end

    describe 'POST v0/coe/document_upload' do
      context 'when uploading attachments' do
        it 'uploads the file successfully' do
          VCR.use_cassette 'lgy/document_upload' do
            attachments = {
              'files' => [{
                'file' => Base64.encode64(File.read('spec/fixtures/files/lgy_file.pdf')),
                'document_type' => 'VA home loan documents',
                'file_type' => 'pdf',
                'file_name' => 'lgy_file.pdf'
              }]
            }

            post('/v0/coe/document_upload', params: attachments)
            expect(response).to have_http_status :ok
            expect(response.body).to eq '201'
          end
        end

        it 'logs upload progress and increments success metrics' do
          VCR.use_cassette 'lgy/document_upload' do
            attachments = {
              'files' => [{
                'file' => Base64.encode64(File.read('spec/fixtures/files/lgy_file.pdf')),
                'document_type' => 'VA home loan documents',
                'file_type' => 'pdf',
                'file_name' => 'lgy_file.pdf'
              }]
            }

            allow(Rails.logger).to receive(:info).and_call_original
            expect(Rails.logger).to receive(:info).with(
              'COE document upload started',
              hash_including(user_uuid: user.uuid, attachment_count: 1, file_types: 'pdf')
            ).and_call_original
            expect(Rails.logger).to receive(:info).with(
              'COE document upload completed successfully',
              hash_including(user_uuid: user.uuid, uploaded_count: 1)
            ).and_call_original
            allow(StatsD).to receive(:increment).and_call_original
            expect(StatsD).to receive(:increment).with('api.lgy_coe.document_upload.success')

            post('/v0/coe/document_upload', params: attachments)
          end
        end
      end

      context 'when receiving 504 from LGY post_document' do
        it 'logs LGY unavailable and increments appropriate metric' do
          VCR.use_cassette 'lgy/document_upload_504' do
            attachments = {
              'files' => [{
                'file' => Base64.encode64(File.read('spec/fixtures/files/lgy_file.pdf')),
                'document_type' => 'VA home loan documents',
                'file_type' => 'pdf',
                'file_name' => 'lgy_file.pdf'
              }]
            }

            allow(Rails.logger).to receive(:info).and_call_original
            expect(Rails.logger).to receive(:info).with(
              'LGY server unavailable or unresponsive',
              hash_including(user_uuid: user.uuid, status: 504, document_type: 'pdf')
            ).and_call_original
            allow(StatsD).to receive(:increment).and_call_original
            expect(StatsD).to receive(:increment).with('api.lgy_coe.post_document.lgy_unavailable')

            post('/v0/coe/document_upload', params: attachments)
            expect(response).to have_http_status(:server_error)
          end
        end
      end

      it 'logs document posting and increments success metric' do
        attachments = {
          'files' => [{
            'file' => Base64.encode64(File.read('spec/fixtures/files/lgy_file.pdf')),
            'document_type' => 'VA home loan documents',
            'file_type' => 'pdf',
            'file_name' => 'lgy_file.pdf'
          }]
        }
        expected_payload = {
          'documentType' => 'pdf',
          'description' => 'VA home loan documents',
          'contentsBase64' => Base64.encode64(File.read('spec/fixtures/files/lgy_file.pdf')),
          'fileName' => 'lgy_file.pdf'
        }

        expected_response = double(:fake_response, status: 201)
        expect_any_instance_of(LGY::Service).to receive(:post_document).with(payload: expected_payload)
                                                                       .and_return(expected_response)

        expect(Rails.logger).to receive(:info).with(
          'COE document upload started',
          hash_including(user_uuid: user.uuid, attachment_count: 1, file_types: 'pdf')
        )
        expect(Rails.logger).to receive(:info).with(
          'Uploading document',
          hash_including(user_uuid: user.uuid, document_index: 1, file_type: 'pdf', file_name: 'lgy_file.pdf')
        )
        expect(Rails.logger).to receive(:info).with(
          'Posting document to LGY',
          hash_including(user_uuid: user.uuid, document_type: 'pdf', file_name: 'lgy_file.pdf')
        )
        expect(Rails.logger).to receive(:info).with(
          'Document posted to LGY successfully',
          hash_including(user_uuid: user.uuid, document_type: 'pdf', status: 201)
        )
        expect(Rails.logger).to receive(:info).with(
          'COE document upload completed successfully',
          hash_including(user_uuid: user.uuid, uploaded_count: 1)
        )
        allow(StatsD).to receive(:increment).and_call_original
        expect(StatsD).to receive(:increment).with('api.lgy_coe.post_document.success')
        expect(StatsD).to receive(:increment).with('api.lgy_coe.document_upload.success')

        post('/v0/coe/document_upload', params: attachments)
        expect(response).to have_http_status(:ok)
        expect(response.body).to eq '201'
      end
    end

    describe 'GET v0/coe/document_download' do
      context 'when document exists' do
        before do
          @lgy_service = double('LGY Service')
          # Simulate http response object
          @res = OpenStruct.new(body: File.read('spec/fixtures/files/lgy_file.pdf'))
          lgy_documents_response_body = [{
            'id' => 123_456_789,
            'document_type' => '705',
            'create_date' => 1_670_530_714_000,
            'description' => nil,
            'mime_type' => 'COE Application First Returned.pdf'
          }]
          lgy_documents_response = double(:lgy_documents_response, body: lgy_documents_response_body)
          allow(@lgy_service).to receive_messages(get_document: @res, get_coe_documents: lgy_documents_response)
          allow_any_instance_of(V0::CoeController).to receive(:lgy_service) { @lgy_service }
        end

        it 'logs download start and success with metrics' do
          expect(Rails.logger).to receive(:info).with(
            'COE document download started',
            hash_including(user_uuid: user.uuid, document_id: '123456789')
          )
          expect(Rails.logger).to receive(:info).with(
            'COE document download successful',
            hash_including(user_uuid: user.uuid, document_id: '123456789')
          )
          allow(StatsD).to receive(:increment).and_call_original
          expect(StatsD).to receive(:increment).with('api.lgy_coe.document_download.success')

          get '/v0/coe/document_download/123456789'
        end

        it 'response code is 200' do
          get '/v0/coe/document_download/123456789'
          expect(response).to have_http_status(:ok)
        end

        it 'response is in PDF format' do
          get '/v0/coe/document_download/123456789'
          expect(response.content_type).to eq('application/pdf')
        end

        it 'response body is correct' do
          get '/v0/coe/document_download/123456789'
          expect(response.body).to eq @res.body
        end
      end

      context 'requested document id not associated with user' do
        before do
          lgy_documents_response_body = [{
            'id' => 23_929_115,
            'document_type' => '252',
            'create_date' => 1_670_530_715_000,
            'description' => '',
            'mime_type' => 'example.png'
          }, {
            'id' => 10_101_010,
            'document_type' => '705',
            'create_date' => 1_670_530_714_000,
            'description' => nil,
            'mime_type' => 'COE Application First Returned.pdf'
          }]
          lgy_documents_response = double(:lgy_documents_response, body: lgy_documents_response_body)
          expect_any_instance_of(LGY::Service).to receive(:get_coe_documents).and_return(lgy_documents_response)
        end

        it '404s' do
          # Note that this ID is not present in lgy_documents_response_body above.
          get '/v0/coe/document_download/12341234'
          expect(response).to have_http_status(:not_found)
          expect(response.content_type).to eq('application/json; charset=utf-8')
          expect(response.body).to include('Record not found')
        end
      end
    end

    describe 'GET v0/coe/documents' do
      it 'logs retrieval and increments success metrics' do
        lgy_documents_response_body = [{
          'id' => 23_929_115,
          'document_type' => 'Veteran Correspondence',
          'create_date' => 1_670_530_715_000,
          'description' => '',
          'mime_type' => 'example.png'
        }, {
          'id' => 10_101_010,
          'document_type' => 'COE Application First Returned',
          'create_date' => 1_670_530_714_000,
          'description' => nil,
          'mime_type' => 'COE Application First Returned.pdf'
        }]
        lgy_documents_response = double(:lgy_documents_response, body: lgy_documents_response_body)
        expect_any_instance_of(LGY::Service).to receive(:get_coe_documents).and_return(lgy_documents_response)

        expect(Rails.logger).to receive(:info).with(
          'COE documents retrieved successfully',
          hash_including(
            user_uuid: user.uuid,
            total_documents: 2,
            filtered_documents: 1
          )
        )
        allow(StatsD).to receive(:increment).and_call_original
        expect(StatsD).to receive(:increment).with('api.lgy_coe.documents.success')

        get '/v0/coe/documents'
      end

      it 'returns notification letters only' do
        lgy_documents_response_body = [{
          'id' => 23_929_115,
          'document_type' => 'Veteran Correspondence',
          'create_date' => 1_670_530_715_000,
          'description' => '',
          'mime_type' => 'example.png'
        }, {
          'id' => 10_101_010,
          'document_type' => 'COE Application First Returned',
          'create_date' => 1_670_530_714_000,
          'description' => nil,
          'mime_type' => 'COE Application First Returned.pdf'
        }]
        lgy_documents_response = double(:lgy_documents_response, body: lgy_documents_response_body)
        expect_any_instance_of(LGY::Service).to receive(:get_coe_documents).and_return(lgy_documents_response)
        get '/v0/coe/documents'
        expected_response_body = {
          'data' => {
            'attributes' => [{
              'id' => 10_101_010,
              'document_type' => 'COE Application First Returned',
              'create_date' => 1_670_530_714_000,
              'description' => nil,
              'mime_type' => 'COE Application First Returned.pdf'
            }]
          }
        }.to_json
        expect(response.body).to eq(expected_response_body)
      end
    end
  end
end
