# frozen_string_literal: true

require 'rails_helper'
require 'claims_evidence_api/service/files'

RSpec.describe 'V0::ClaimsEvidence', type: :request do
  let(:user) { create(:user, :loa3, :legacy_icn) }
  let(:file) { fixture_file_upload('doctors-note.pdf') }
  let(:valid_doc_type_id) { 34 } # Correspondence (L023)
  let(:ce_success) { build(:claims_evidence_service_files_response, :success) }

  before do
    allow(Common::VirusScan).to receive(:scan).and_return(true)
    allow(Flipper).to receive(:enabled?).and_call_original
    allow(Flipper).to receive(:enabled?)
      .with(:cst_supplemental_claims_evidence_upload, instance_of(User))
      .and_return(true)
  end

  describe 'POST /v0/claims_evidence' do
    context 'when unauthenticated' do
      it 'returns 401' do
        post '/v0/claims_evidence', params: { file:, documentTypeId: valid_doc_type_id }
        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when authenticated' do
      before { sign_in_as(user) }

      context 'when the user is not LOA3' do
        let(:user) { create(:user, :loa1) }

        it 'returns 403' do
          post '/v0/claims_evidence', params: { file:, documentTypeId: valid_doc_type_id }
          expect(response).to have_http_status(:forbidden)
        end
      end

      context 'when the feature flag is disabled' do
        before do
          allow(Flipper).to receive(:enabled?)
            .with(:cst_supplemental_claims_evidence_upload, instance_of(User))
            .and_return(false)
        end

        it 'returns 404' do
          post '/v0/claims_evidence', params: { file:, documentTypeId: valid_doc_type_id }
          expect(response).to have_http_status(:not_found)
        end
      end

      context 'when the feature flag is enabled' do
        context 'with a missing file' do
          it 'returns 400' do
            post '/v0/claims_evidence', params: { documentTypeId: valid_doc_type_id }
            expect(response).to have_http_status(:bad_request)
          end

          it 'logs the failure with document context when documentTypeId is present' do
            allow(Rails.logger).to receive(:error)
            post '/v0/claims_evidence', params: { documentTypeId: valid_doc_type_id }
            expect(Rails.logger).to have_received(:error).with(
              'ClaimsEvidenceController#create upload failed',
              hash_including(document_type_id: valid_doc_type_id, file_size: nil, content_type: nil)
            )
          end
        end

        context 'with a non-file value for file' do
          it 'returns 400' do
            post '/v0/claims_evidence', params: { file: 'not-a-file', documentTypeId: valid_doc_type_id }
            expect(response).to have_http_status(:bad_request)
          end

          it 'logs the failure with document context when documentTypeId is present' do
            allow(Rails.logger).to receive(:error)
            post '/v0/claims_evidence', params: { file: 'not-a-file', documentTypeId: valid_doc_type_id }
            expect(Rails.logger).to have_received(:error).with(
              'ClaimsEvidenceController#create upload failed',
              hash_including(document_type_id: valid_doc_type_id, file_size: nil, content_type: nil)
            )
          end
        end

        context 'with a missing documentTypeId' do
          it 'returns 400' do
            post '/v0/claims_evidence', params: { file: }
            expect(response).to have_http_status(:bad_request)
          end
        end

        context 'with an unsupported documentTypeId' do
          it 'returns 422' do
            post '/v0/claims_evidence', params: { file:, documentTypeId: 9999 }
            expect(response).to have_http_status(:unprocessable_entity)
          end
        end

        context 'with a malformed documentTypeId' do
          it 'returns 422 for a non-numeric string' do
            post '/v0/claims_evidence', params: { file:, documentTypeId: '34abc' }
            expect(response).to have_http_status(:unprocessable_entity)
          end

          it 'returns 422 for an array value' do
            post '/v0/claims_evidence', params: { file:, documentTypeId: [34] }
            expect(response).to have_http_status(:unprocessable_entity)
          end
        end

        context 'with valid params' do
          around do |example|
            Timecop.freeze(Time.utc(2026, 1, 1, 12, 0, 0)) { example.run }
          end

          before do
            allow_any_instance_of(ClaimsEvidenceApi::Service::Files)
              .to receive(:upload)
              .and_return(ce_success)
          end

          it 'returns 200 with uuid and currentVersionUuid only' do
            post '/v0/claims_evidence', params: { file:, documentTypeId: valid_doc_type_id }
            expect(response).to have_http_status(:ok)
            body = JSON.parse(response.body)
            expect(body['uuid']).to eq('c30626c9-954d-4dd1-9f70-1e38756d9d97')
            expect(body['currentVersionUuid']).to eq('c30626c9-954d-4dd1-9f70-1e38756d9d98')
            expect(body.keys).to match_array(%w[uuid currentVersionUuid])
          end

          it 'calls upload with the correct provider_data' do
            expected_provider_data = hash_including(
              contentSource: ClaimsEvidenceApi::CONTENT_SOURCE,
              documentTypeId: valid_doc_type_id,
              dateVaReceivedDocument: Time.zone.now.in_time_zone(ClaimsEvidenceApi::TIMEZONE).strftime('%Y-%m-%d')
            )
            expect_any_instance_of(ClaimsEvidenceApi::Service::Files)
              .to receive(:upload)
              .with(satisfy { |path|
                      File.basename(path).start_with?('doctors-note')
                    }, provider_data: expected_provider_data)
              .and_return(ce_success)
            post '/v0/claims_evidence', params: { file:, documentTypeId: valid_doc_type_id }
          end

          it 'sets the folder identifier from the user ICN' do
            expect_any_instance_of(ClaimsEvidenceApi::Service::Files)
              .to receive(:folder_identifier=)
              .with("VETERAN:ICN:#{user.icn}")
              .and_call_original
            post '/v0/claims_evidence', params: { file:, documentTypeId: valid_doc_type_id }
          end

          it 'increments the success counter tagged with documentTypeId' do
            allow(StatsD).to receive(:increment)
            post '/v0/claims_evidence', params: { file:, documentTypeId: valid_doc_type_id }
            expect(StatsD).to have_received(:increment).with(
              'api.claims_evidence.upload.success',
              tags: ["documentTypeId:#{valid_doc_type_id}"]
            )
          end
        end

        context 'when the file contains a virus' do
          before do
            allow_any_instance_of(ClaimsEvidenceApi::Service::Files)
              .to receive(:upload)
              .and_raise(ClaimsEvidenceApi::Service::Files::VirusFound)
          end

          it 'returns 422' do
            post '/v0/claims_evidence', params: { file:, documentTypeId: valid_doc_type_id }
            expect(response).to have_http_status(:unprocessable_entity)
          end
        end

        context 'when CE returns an error' do
          before do
            allow_any_instance_of(ClaimsEvidenceApi::Service::Files)
              .to receive(:upload)
              .and_raise(build(:claims_evidence_service_files_error, :error))
          end

          it 'returns 503' do
            post '/v0/claims_evidence', params: { file:, documentTypeId: valid_doc_type_id }
            expect(response).to have_http_status(:service_unavailable)
          end

          it 'logs a structured failure entry with document context' do
            allow(Rails.logger).to receive(:error)
            post '/v0/claims_evidence', params: { file:, documentTypeId: valid_doc_type_id }
            expect(Rails.logger).to have_received(:error).with(
              'ClaimsEvidenceController#create upload failed',
              hash_including(
                document_type_id: valid_doc_type_id,
                file_size: kind_of(Integer),
                content_type: kind_of(String)
              )
            )
          end

          it 'does not increment the success counter' do
            allow(StatsD).to receive(:increment)
            post '/v0/claims_evidence', params: { file:, documentTypeId: valid_doc_type_id }
            expect(StatsD).not_to have_received(:increment).with(
              'api.claims_evidence.upload.success', anything
            )
          end
        end
      end
    end
  end
end
