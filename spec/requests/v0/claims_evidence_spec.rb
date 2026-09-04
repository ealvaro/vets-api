# frozen_string_literal: true

require 'rails_helper'
require 'claims_evidence_api/service/files'

RSpec.describe 'V0::ClaimsEvidence', type: :request do
  let(:user) { create(:user, :loa3, :legacy_icn) }
  let(:file) { fixture_file_upload('doctors-note.pdf') }
  let(:valid_doc_type_id) { 34 } # Correspondence (L023)
  let(:sc_id) { 'SC10879' }
  let(:ce_success) { build(:claims_evidence_service_files_response, :success) }

  before do
    allow(Common::VirusScan).to receive(:scan).and_return(true)
    allow(Flipper).to receive(:enabled?).and_call_original
    allow(Flipper).to receive(:enabled?)
      .with(:cst_supplemental_claims_evidence_upload, instance_of(User))
      .and_return(true)
  end

  describe 'POST /v0/claims_evidence' do
    def post_upload(**overrides)
      params = { file:, documentTypeId: valid_doc_type_id, supplementalClaimId: sc_id }
               .merge(overrides).compact
      post '/v0/claims_evidence', params:
    end

    # The DOC_UPLOAD_* code, or the prose sentence on the paths that still send one.
    def error_detail
      JSON.parse(response.body)['errors'].first['detail']
    end

    shared_examples 'a rejected file' do |code:|
      it "returns 422 with #{code}" do
        expect_any_instance_of(ClaimsEvidenceApi::Service::Files).not_to receive(:upload)

        post_upload

        expect(response).to have_http_status(:unprocessable_entity)
        expect(error_detail).to eq(code)
      end
    end

    # The log carries whatever the earlier parses established, so a file rejected before
    # supplementalClaimId is read still names the document type it was filed under.
    shared_examples 'a logged failure with partial context' do |**bad_params|
      it 'logs the failure with document context when documentTypeId is present' do
        allow(Rails.logger).to receive(:error)

        post_upload(supplementalClaimId: nil, **bad_params)

        expect(Rails.logger).to have_received(:error).with(
          'ClaimsEvidenceController#create upload failed',
          hash_including(document_type_id: valid_doc_type_id, supplemental_claim_id: nil,
                         file_size: nil, content_type: nil)
        )
      end
    end

    context 'when unauthenticated' do
      it 'returns 401' do
        post_upload
        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when authenticated' do
      before { sign_in_as(user) }

      context 'when the user is not LOA3' do
        let(:user) { create(:user, :loa1) }

        it 'returns 403' do
          post_upload
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
          post_upload
          expect(response).to have_http_status(:not_found)
        end
      end

      context 'when the feature flag is enabled' do
        # These three answer 400 rather than 422, so they carry no DOC_UPLOAD_* code.
        context 'with a missing file' do
          it 'returns 400' do
            post_upload(file: nil)
            expect(response).to have_http_status(:bad_request)
          end

          it_behaves_like 'a logged failure with partial context', file: nil
        end

        context 'with a non-file value for file' do
          it 'returns 400' do
            post_upload(file: 'not-a-file')
            expect(response).to have_http_status(:bad_request)
          end

          it_behaves_like 'a logged failure with partial context', file: 'not-a-file'
        end

        context 'with a missing documentTypeId' do
          it 'returns 400' do
            post_upload(documentTypeId: nil)
            expect(response).to have_http_status(:bad_request)
          end
        end

        context 'with an unsupported documentTypeId' do
          it 'returns 422 with DOC_UPLOAD_UNSUPPORTED_DOC_TYPE_ID' do
            post_upload(documentTypeId: 9999)
            expect(response).to have_http_status(:unprocessable_entity)
            expect(error_detail).to eq('DOC_UPLOAD_UNSUPPORTED_DOC_TYPE_ID')
          end
        end

        context 'with a malformed documentTypeId' do
          it 'returns 422 with DOC_UPLOAD_INVALID_DOC_TYPE_ID for a non-numeric string' do
            post_upload(documentTypeId: '34abc')
            expect(response).to have_http_status(:unprocessable_entity)
            expect(error_detail).to eq('DOC_UPLOAD_INVALID_DOC_TYPE_ID')
          end

          it 'returns 422 with DOC_UPLOAD_INVALID_DOC_TYPE_ID for an array value' do
            post_upload(documentTypeId: [34])
            expect(response).to have_http_status(:unprocessable_entity)
            expect(error_detail).to eq('DOC_UPLOAD_INVALID_DOC_TYPE_ID')
          end
        end

        context 'with a missing supplementalClaimId' do
          it 'returns 422 with DOC_UPLOAD_MISSING_CLAIM_ID' do
            post_upload(supplementalClaimId: nil)
            expect(response).to have_http_status(:unprocessable_entity)
            expect(error_detail).to eq('DOC_UPLOAD_MISSING_CLAIM_ID')
          end

          it 'logs the failure with supplemental_claim_id nil' do
            allow(Rails.logger).to receive(:error)
            post_upload(supplementalClaimId: nil)
            expect(Rails.logger).to have_received(:error).with(
              'ClaimsEvidenceController#create upload failed',
              hash_including(supplemental_claim_id: nil, document_type_id: valid_doc_type_id)
            )
          end
        end

        context 'with a blank supplementalClaimId' do
          it 'returns 422 with DOC_UPLOAD_MISSING_CLAIM_ID' do
            post_upload(supplementalClaimId: ' ')
            expect(response).to have_http_status(:unprocessable_entity)
            expect(error_detail).to eq('DOC_UPLOAD_MISSING_CLAIM_ID')
          end
        end

        context 'with a malformed supplementalClaimId' do
          it 'returns 422 with DOC_UPLOAD_INVALID_CLAIM_ID for a non-SC identifier' do
            post_upload(supplementalClaimId: 'ABC123')
            expect(response).to have_http_status(:unprocessable_entity)
            expect(error_detail).to eq('DOC_UPLOAD_INVALID_CLAIM_ID')
          end

          it 'returns 422 with DOC_UPLOAD_INVALID_CLAIM_ID for a lowercase prefix' do
            post_upload(supplementalClaimId: 'sc10879')
            expect(response).to have_http_status(:unprocessable_entity)
            expect(error_detail).to eq('DOC_UPLOAD_INVALID_CLAIM_ID')
          end
        end

        context 'with an empty file' do
          let(:file) { fixture_file_upload('empty-file.jpg', 'image/jpeg') }

          it_behaves_like 'a rejected file', code: 'DOC_UPLOAD_EMPTY_FILE'
        end

        context 'with a file over the size limit' do
          before { stub_const('V0::ClaimsEvidenceController::MAX_FILE_SIZE', 10) }

          it_behaves_like 'a rejected file', code: 'DOC_UPLOAD_FILE_TOO_LARGE'

          it 'applies to non-PDFs too' do
            post_upload(file: fixture_file_upload('doctors-note.png', 'image/png'))
            expect(response).to have_http_status(:unprocessable_entity)
            expect(error_detail).to eq('DOC_UPLOAD_FILE_TOO_LARGE')
          end
        end

        context 'with an unsupported file type' do
          let(:file) { fixture_file_upload('va.gif', 'image/gif') }

          it_behaves_like 'a rejected file', code: 'DOC_UPLOAD_UNSUPPORTED_TYPE'

          it 'rejects a file with no extension' do
            no_extension = Rack::Test::UploadedFile.new(
              Rails.root.join('spec', 'fixtures', 'files', 'doctors-note.pdf'),
              'application/pdf',
              original_filename: 'noextension'
            )

            post_upload(file: no_extension)
            expect(response).to have_http_status(:unprocessable_entity)
            expect(error_detail).to eq('DOC_UPLOAD_UNSUPPORTED_TYPE')
          end

          it 'accepts each type the form offers' do
            allow_any_instance_of(ClaimsEvidenceApi::Service::Files).to receive(:upload).and_return(ce_success)

            %w[doctors-note.pdf doctors-note.png doctors-note.jpg doctors-note.bmp].each do |name|
              post_upload(file: fixture_file_upload(name))
              expect(response).to have_http_status(:ok), "#{name} was rejected"
            end
          end
        end

        context 'when the file contains a virus' do
          before do
            allow_any_instance_of(ClaimsEvidenceApi::Service::Files)
              .to receive(:upload)
              .and_raise(ClaimsEvidenceApi::Service::Files::VirusFound)
          end

          it 'returns 422 with DOC_UPLOAD_SCAN_FAILED' do
            post_upload
            expect(response).to have_http_status(:unprocessable_entity)
            expect(error_detail).to eq('DOC_UPLOAD_SCAN_FAILED')
          end
        end

        context 'with valid params' do
          before do
            allow_any_instance_of(ClaimsEvidenceApi::Service::Files)
              .to receive(:upload)
              .and_return(ce_success)
          end

          it 'returns 200 with uuid and currentVersionUuid only' do
            post_upload
            expect(response).to have_http_status(:ok)
            body = JSON.parse(response.body)
            expect(body['uuid']).to eq('c30626c9-954d-4dd1-9f70-1e38756d9d97')
            expect(body['currentVersionUuid']).to eq('c30626c9-954d-4dd1-9f70-1e38756d9d98')
            expect(body.keys).to match_array(%w[uuid currentVersionUuid])
          end

          it 'refuses a second upload of the same file with DOC_UPLOAD_DUPLICATE' do
            post_upload
            expect(response).to have_http_status(:ok)

            post_upload

            expect(response).to have_http_status(:unprocessable_entity)
            expect(error_detail).to eq('DOC_UPLOAD_DUPLICATE')
          end

          it 'answers DOC_UPLOAD_UNSUPPORTED_NAME when the filename has no ASCII equivalent' do
            allow(ClaimsEvidence::ContentName).to receive(:sanitize)
              .and_raise(ClaimsEvidence::ContentName::Unsupported)

            post_upload

            expect(response).to have_http_status(:unprocessable_entity)
            expect(error_detail).to eq('DOC_UPLOAD_UNSUPPORTED_NAME')
          end

          # The name belongs to a different document in the eFolder, which only the Veteran can
          # resolve -- unhandled this would be a 500 with no indication of what to do.
          it 'answers DOC_UPLOAD_NAME_TAKEN when the name belongs to another document' do
            allow_any_instance_of(ClaimsEvidence::UploadEvidence)
              .to receive(:upload_document).and_raise(ClaimsEvidence::UploadEvidence::ContentNameTaken)

            post_upload

            expect(response).to have_http_status(:unprocessable_entity)
            expect(error_detail).to eq('DOC_UPLOAD_NAME_TAKEN')
          end

          it 'does not emit an error-level failure log for a duplicate' do
            post_upload

            allow(Rails.logger).to receive(:error).and_call_original
            post_upload

            expect(Rails.logger).not_to have_received(:error).with(
              'ClaimsEvidenceController#create upload failed', anything
            )
          end

          it 'does not block a different file on the same claim' do
            post_upload
            expect(response).to have_http_status(:ok)

            post_upload(file: fixture_file_upload('doctors-note.png', 'image/png'))
            expect(response).to have_http_status(:ok)
          end
        end

        context 'with an encrypted PDF' do
          let(:file) { fixture_file_upload('locked_pdf_password_is_test.pdf', 'application/pdf') }

          before do
            allow_any_instance_of(ClaimsEvidenceApi::Service::Files)
              .to receive(:upload)
              .and_return(ce_success)
          end

          context 'and the correct password' do
            it 'returns 200 and records the size the veteran uploaded, not the decrypted rewrite' do
              expect { post_upload(password: 'test') }.to change(EvidenceSubmission, :count).by(1)
              expect(response).to have_http_status(:ok)
              expect(EvidenceSubmission.last.file_size).to eq(file.size)
            end

            it 'sends Claims Evidence a decrypted file' do
              uploaded_encrypted = nil
              allow_any_instance_of(ClaimsEvidenceApi::Service::Files).to receive(:upload) do |_service, path, **|
                uploaded_encrypted = HexaPDF::Document.open(path).encrypted?
                ce_success
              end

              post_upload(password: 'test')
              expect(uploaded_encrypted).to be(false)
            end
          end

          context 'and an incorrect password' do
            it 'returns 422 with DOC_UPLOAD_INCORRECT_PASSWORD' do
              post_upload(password: 'not-the-password')
              expect(response).to have_http_status(:unprocessable_entity)
              expect(error_detail).to eq('DOC_UPLOAD_INCORRECT_PASSWORD')
            end

            it 'does not emit an error-level failure log' do
              allow(Rails.logger).to receive(:error).and_call_original

              post_upload(password: 'not-the-password')

              expect(Rails.logger).not_to have_received(:error).with(
                'ClaimsEvidenceController#create upload failed', anything
              )
            end

            # A typo must not cost the veteran the lock's full TTL.
            it 'frees the lock so the correct password can be retried immediately' do
              post_upload(password: 'not-the-password')
              expect(response).to have_http_status(:unprocessable_entity)

              post_upload(password: 'test')
              expect(response).to have_http_status(:ok)
            end
          end

          context 'and no password' do
            it_behaves_like 'a rejected file', code: 'DOC_UPLOAD_ENCRYPTED_PDF'
          end
        end

        context 'when CE returns a success status with a body we cannot build a response from' do
          before do
            allow_any_instance_of(ClaimsEvidenceApi::Service::Files)
              .to receive(:upload)
              .and_return(double(reason_phrase: 'OK', status: 200, body: 'not-a-hash'))
          end

          it 'returns 500 rather than a success the frontend cannot read' do
            post_upload
            expect(response).to have_http_status(:internal_server_error)
          end
        end

        context 'when CE returns an error' do
          before do
            allow_any_instance_of(ClaimsEvidenceApi::Service::Files)
              .to receive(:upload)
              .and_raise(build(:claims_evidence_service_files_error, :error))
          end

          it 'returns 503' do
            post_upload
            expect(response).to have_http_status(:service_unavailable)
          end

          it 'logs a structured failure entry with document context' do
            allow(Rails.logger).to receive(:error)
            post_upload
            expect(Rails.logger).to have_received(:error).with(
              'ClaimsEvidenceController#create upload failed',
              hash_including(
                document_type_id: valid_doc_type_id,
                supplemental_claim_id: sc_id,
                file_size: kind_of(Integer),
                content_type: kind_of(String)
              )
            )
          end
        end

        # The breaker short-circuits inside the Faraday stack, so this context deliberately
        # leaves Files#upload unstubbed: an open breaker means nothing reaches Claims Evidence.
        context 'when the Claims Evidence breaker is open' do
          let(:breakers_service) { ClaimsEvidenceApi::Configuration.instance.breakers_service }

          before { breakers_service.begin_forced_outage! }

          after { breakers_service.end_forced_outage! }

          it 'returns 503 naming the outage' do
            post_upload
            expect(response).to have_http_status(:service_unavailable)
            expect(error_detail).to match(/outage has been reported on the ClaimsEvidenceApi/)
          end

          it 'does not persist an EvidenceSubmission' do
            expect { post_upload }.not_to change(EvidenceSubmission, :count)
          end

          it 'increments the upload failure counter with the outage error class' do
            allow(StatsD).to receive(:increment).and_call_original
            post_upload
            expect(StatsD).to have_received(:increment).with(
              'api.claims_evidence.upload.failure',
              tags: ClaimsEvidence::Metrics::TAGS + ['error_class:Breakers::OutageException',
                                                     "document_type_id:#{valid_doc_type_id}"]
            )
          end
        end
      end
    end
  end
end
