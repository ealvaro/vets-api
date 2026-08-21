# frozen_string_literal: true

require 'rails_helper'
require 'claims_evidence_api/service/files'

RSpec.describe 'V0::ClaimsEvidence', type: :request do
  let(:user) { create(:user, :loa3, :legacy_icn) }
  let(:file) { fixture_file_upload('doctors-note.pdf') }
  let(:valid_doc_type_id) { 34 } # Correspondence (L023)
  let(:sc_id) { 'SC10879' }
  let(:ce_success) { build(:claims_evidence_service_files_response, :success) }
  # Ownership tags prefixed onto every metric. The success counter below asserts the literal
  # values; everywhere else we reference the constant so the tag list lives in one place.
  let(:base_tags) { V0::ClaimsEvidenceController::STATSD_TAGS }

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
        context 'with a missing file' do
          it 'returns 400' do
            post_upload(file: nil)
            expect(response).to have_http_status(:bad_request)
          end

          it 'increments the validation failure counter with reason:missing_file' do
            allow(StatsD).to receive(:increment).and_call_original
            post_upload(file: nil)
            expect(StatsD).to have_received(:increment).with(
              'api.claims_evidence.validation.failure', tags: base_tags + ['reason:missing_file']
            )
          end

          it 'logs the failure with document context when documentTypeId is present' do
            allow(Rails.logger).to receive(:error)
            post_upload(file: nil, supplementalClaimId: nil)
            expect(Rails.logger).to have_received(:error).with(
              'ClaimsEvidenceController#create upload failed',
              hash_including(document_type_id: valid_doc_type_id, supplemental_claim_id: nil,
                             file_size: nil, content_type: nil)
            )
          end
        end

        context 'with a non-file value for file' do
          it 'returns 400' do
            post_upload(file: 'not-a-file')
            expect(response).to have_http_status(:bad_request)
          end

          it 'increments the validation failure counter with reason:invalid_file' do
            allow(StatsD).to receive(:increment).and_call_original
            post_upload(file: 'not-a-file')
            expect(StatsD).to have_received(:increment).with(
              'api.claims_evidence.validation.failure', tags: base_tags + ['reason:invalid_file']
            )
          end

          it 'logs the failure with document context when documentTypeId is present' do
            allow(Rails.logger).to receive(:error)
            post_upload(file: 'not-a-file', supplementalClaimId: nil)
            expect(Rails.logger).to have_received(:error).with(
              'ClaimsEvidenceController#create upload failed',
              hash_including(document_type_id: valid_doc_type_id, supplemental_claim_id: nil,
                             file_size: nil, content_type: nil)
            )
          end
        end

        context 'with a missing documentTypeId' do
          it 'returns 400' do
            post_upload(documentTypeId: nil)
            expect(response).to have_http_status(:bad_request)
          end

          it 'increments the validation failure counter with reason:missing_document_type_id' do
            allow(StatsD).to receive(:increment).and_call_original
            post_upload(documentTypeId: nil)
            expect(StatsD).to have_received(:increment).with(
              'api.claims_evidence.validation.failure', tags: base_tags + ['reason:missing_document_type_id']
            )
          end
        end

        context 'with an unsupported documentTypeId' do
          it 'returns 422' do
            post_upload(documentTypeId: 9999)
            expect(response).to have_http_status(:unprocessable_entity)
          end

          it 'increments the validation failure counter with reason:unsupported_document_type_id' do
            allow(StatsD).to receive(:increment).and_call_original
            post_upload(documentTypeId: 9999)
            expect(StatsD).to have_received(:increment).with(
              'api.claims_evidence.validation.failure',
              tags: base_tags + ['reason:unsupported_document_type_id']
            )
          end
        end

        context 'with a malformed documentTypeId' do
          it 'returns 422 for a non-numeric string' do
            post_upload(documentTypeId: '34abc')
            expect(response).to have_http_status(:unprocessable_entity)
          end

          it 'returns 422 for an array value' do
            post_upload(documentTypeId: [34])
            expect(response).to have_http_status(:unprocessable_entity)
          end

          it 'increments the validation failure counter with reason:malformed_document_type_id' do
            allow(StatsD).to receive(:increment).and_call_original
            post_upload(documentTypeId: '34abc')
            expect(StatsD).to have_received(:increment).with(
              'api.claims_evidence.validation.failure',
              tags: base_tags + ['reason:malformed_document_type_id']
            )
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
            post_upload
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
            post_upload
          end

          it 'sets the folder identifier from the user ICN' do
            expect_any_instance_of(ClaimsEvidenceApi::Service::Files)
              .to receive(:folder_identifier=)
              .with("VETERAN:ICN:#{user.icn}")
              .and_call_original
            post_upload
          end

          it 'increments the success counter tagged with documentTypeId and logs the document type name' do
            allow(StatsD).to receive(:increment).and_call_original
            allow(Rails.logger).to receive(:info)

            post_upload

            expect(StatsD).to have_received(:increment).with(
              'api.claims_evidence.upload.success',
              tags: ['service:claims-evidence',
                     'team:benefits-management-tools',
                     'itportfolio:benefits-delivery',
                     'dependency:claims-evidence-api',
                     "document_type_id:#{valid_doc_type_id}"]
            )
            expect(Rails.logger).to have_received(:info).with(
              'ClaimsEvidenceController#create upload success',
              document_type: 'Correspondence'
            )
          end

          # The upload is done and the record is saved before this telemetry runs, so a broken
          # metric or log must not fail the request or report it as a failure.
          context 'and the success telemetry itself fails' do
            it 'counts the success once and no failure when the logger raises after the counter' do
              allow(StatsD).to receive(:increment).and_call_original
              allow(Rails.logger).to receive(:info).and_call_original
              allow(Rails.logger).to receive(:info)
                .with('ClaimsEvidenceController#create upload success', any_args)
                .and_raise(StandardError, 'logger down')

              post_upload

              expect(response).to have_http_status(:ok)
              expect(JSON.parse(response.body)['uuid']).to eq('c30626c9-954d-4dd1-9f70-1e38756d9d97')
              expect(StatsD).to have_received(:increment).with(
                'api.claims_evidence.upload.success', anything
              )
              expect(StatsD).not_to have_received(:increment).with(
                'api.claims_evidence.upload.failure', anything
              )
            end

            it 'still returns 200 when the counter raises, even though the metric is lost' do
              allow(StatsD).to receive(:increment).and_call_original
              allow(StatsD).to receive(:increment)
                .with('api.claims_evidence.upload.success', anything)
                .and_raise(StandardError, 'statsd down')

              post_upload

              expect(response).to have_http_status(:ok)
              expect(JSON.parse(response.body)['uuid']).to eq('c30626c9-954d-4dd1-9f70-1e38756d9d97')
              expect(StatsD).not_to have_received(:increment).with(
                'api.claims_evidence.upload.failure', anything
              )
            end
          end

          it 'persists a SUCCESS EvidenceSubmission with caseflow_claim_id and file metadata' do
            expect { post_upload }.to change(EvidenceSubmission, :count).by(1)

            es = EvidenceSubmission.last
            expect(es.caseflow_claim_id).to eq(sc_id)
            expect(es.upload_status).to eq(BenefitsDocuments::Constants::UPLOAD_STATUS[:SUCCESS])
            expect(es.user_account_id).to eq(user.user_account_uuid)
            expect(es.claim_id).to be_nil
            expect(es.file_size).to be > 0
            expect(es.delete_date).to be_within(1.minute).of(60.days.from_now)
            metadata = JSON.parse(es.template_metadata)
            expect(metadata.dig('personalisation', 'file_name')).to eq('doctors-note.pdf')
            expect(metadata.dig('personalisation', 'document_type')).to eq('Correspondence')
          end

          context 'and EvidenceSubmission persistence fails' do
            before do
              allow(EvidenceSubmission).to receive(:create!).and_raise(StandardError.new('boom'))
            end

            it 'still returns 200 because the document is already in the eFolder' do
              post_upload
              expect(response).to have_http_status(:ok)
            end

            it 'increments the persistence failure statsd counter tagged with the error class' do
              allow(StatsD).to receive(:increment).and_call_original
              post_upload
              expect(StatsD).to have_received(:increment)
                .with('api.claims_evidence.persist.failure', tags: base_tags + ['error_class:StandardError'])
            end

            it 'logs the failure with a scrubbed message and error_class' do
              allow(Logging::Helper::DataScrubber).to receive(:scrub).and_return('[scrubbed]')
              allow(Rails.logger).to receive(:error)

              post_upload

              expect(Logging::Helper::DataScrubber).to have_received(:scrub).with('boom')
              expect(Rails.logger).to have_received(:error).with(
                'ClaimsEvidenceController#persist_evidence_submission failed',
                hash_including(
                  document_type_id: valid_doc_type_id,
                  supplemental_claim_id: sc_id,
                  error_class: 'StandardError',
                  error: '[scrubbed]'
                )
              )
            end

            it 'captures the data needed to recreate the EvidenceSubmission by hand' do
              expect { post_upload }.to change(PersonalInformationLog, :count).by(1)

              pii_log = PersonalInformationLog.last
              expect(pii_log.error_class).to eq('ClaimsEvidenceController#persist_evidence_submission')
              expect(pii_log.data).to include(
                'caseflow_claim_id' => sc_id,
                'user_account_id' => user.user_account_uuid,
                'icn' => user.icn,
                'document_type_id' => valid_doc_type_id,
                'document_type' => 'Correspondence',
                'file_name' => 'doctors-note.pdf',
                'upload_status' => BenefitsDocuments::Constants::UPLOAD_STATUS[:SUCCESS],
                'claims_evidence_uuid' => ce_success.body['uuid'],
                'claims_evidence_current_version_uuid' => ce_success.body['currentVersionUuid']
              )
              expect(pii_log.data['file_size']).to be > 0
            end

            context 'when the backfill capture also fails' do
              before do
                allow(PersonalInformationLog).to receive(:create).and_raise(StandardError.new('db down'))
              end

              it 'still returns 200 rather than 500 a document that was filed successfully' do
                post_upload
                expect(response).to have_http_status(:ok)
              end

              it 'increments the unrecoverable counter and logs the CE uuid so the document can still be traced' do
                allow(StatsD).to receive(:increment).and_call_original
                allow(Rails.logger).to receive(:error)

                post_upload

                expect(StatsD).to have_received(:increment)
                  .with('api.claims_evidence.persist.unrecoverable',
                        tags: base_tags + ['error_class:StandardError'])
                expect(Rails.logger).to have_received(:error).with(
                  'ClaimsEvidenceController#capture_submission_for_backfill failed',
                  hash_including(
                    supplemental_claim_id: sc_id,
                    user_account_uuid: user.user_account_uuid,
                    document_type_id: valid_doc_type_id,
                    claims_evidence_uuid: ce_success.body['uuid'],
                    error_class: 'StandardError'
                  )
                )
              end
            end
          end
        end

        context 'with a missing supplementalClaimId' do
          before do
            allow_any_instance_of(ClaimsEvidenceApi::Service::Files)
              .to receive(:upload)
              .and_return(ce_success)
          end

          it 'returns 422' do
            post_upload(supplementalClaimId: nil)
            expect(response).to have_http_status(:unprocessable_entity)
          end

          it 'includes the supplementalClaimId error detail' do
            post_upload(supplementalClaimId: nil)
            expect(JSON.parse(response.body)['errors'].first['detail']).to eq('supplementalClaimId is required')
          end

          it 'does not persist an EvidenceSubmission' do
            expect { post_upload(supplementalClaimId: nil) }.not_to change(EvidenceSubmission, :count)
          end

          it 'logs the failure with supplemental_claim_id nil' do
            allow(Rails.logger).to receive(:error)
            post_upload(supplementalClaimId: nil)
            expect(Rails.logger).to have_received(:error).with(
              'ClaimsEvidenceController#create upload failed',
              hash_including(supplemental_claim_id: nil, document_type_id: valid_doc_type_id)
            )
          end

          it 'increments the validation failure counter with reason:missing_supplemental_claim_id' do
            allow(StatsD).to receive(:increment).and_call_original
            post_upload(supplementalClaimId: nil)
            expect(StatsD).to have_received(:increment).with(
              'api.claims_evidence.validation.failure',
              tags: base_tags + ['reason:missing_supplemental_claim_id']
            )
          end
        end

        context 'with a blank supplementalClaimId' do
          it 'returns 422' do
            post_upload(supplementalClaimId: ' ')
            expect(response).to have_http_status(:unprocessable_entity)
          end
        end

        context 'with a malformed supplementalClaimId' do
          it 'returns 422 for a non-SC identifier' do
            post_upload(supplementalClaimId: 'ABC123')
            expect(response).to have_http_status(:unprocessable_entity)
          end

          it 'includes the supplementalClaimId format error detail' do
            post_upload(supplementalClaimId: 'sc10879')
            expect(JSON.parse(response.body)['errors'].first['detail'])
              .to eq('supplementalClaimId must be in the format SC followed by digits (e.g. SC10879)')
          end

          it 'does not persist an EvidenceSubmission' do
            expect { post_upload(supplementalClaimId: 'foo') }.not_to change(EvidenceSubmission, :count)
          end

          it 'increments the validation failure counter with reason:malformed_supplemental_claim_id' do
            allow(StatsD).to receive(:increment).and_call_original
            post_upload(supplementalClaimId: 'foo')
            expect(StatsD).to have_received(:increment).with(
              'api.claims_evidence.validation.failure',
              tags: base_tags + ['reason:malformed_supplemental_claim_id']
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
            post_upload
            expect(response).to have_http_status(:unprocessable_entity)
          end

          it 'does not persist an EvidenceSubmission' do
            expect { post_upload }.not_to change(EvidenceSubmission, :count)
          end

          it 'increments the upload failure counter with reason:virus' do
            allow(StatsD).to receive(:increment).and_call_original
            post_upload
            expect(StatsD).to have_received(:increment).with(
              'api.claims_evidence.upload.failure',
              tags: base_tags + ['reason:virus', "document_type_id:#{valid_doc_type_id}"]
            )
          end
        end

        context 'when CE returns a success status with a body we cannot build a response from' do
          let(:malformed_response) { double(reason_phrase: 'OK', status: 200, body: 'not-a-hash') }

          before do
            allow_any_instance_of(ClaimsEvidenceApi::Service::Files)
              .to receive(:upload)
              .and_return(malformed_response)
          end

          it 'counts the request once, as a failure, rather than as both a success and a failure' do
            allow(StatsD).to receive(:increment).and_call_original

            post_upload

            expect(StatsD).not_to have_received(:increment).with(
              'api.claims_evidence.upload.success', anything
            )
            expect(StatsD).to have_received(:increment).with(
              'api.claims_evidence.upload.failure',
              tags: base_tags + ['error_class:TypeError', "document_type_id:#{valid_doc_type_id}"]
            )
          end

          it 'still persists the EvidenceSubmission because the document is already in the eFolder' do
            expect { post_upload }.to change(EvidenceSubmission, :count).by(1)
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

          it 'does not persist an EvidenceSubmission' do
            expect { post_upload }.not_to change(EvidenceSubmission, :count)
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

          it 'does not increment the upload success counter' do
            allow(StatsD).to receive(:increment).and_call_original
            post_upload
            expect(StatsD).not_to have_received(:increment).with(
              'api.claims_evidence.upload.success', anything
            )
          end

          it 'increments the upload failure counter with error_class' do
            allow(StatsD).to receive(:increment).and_call_original
            post_upload
            expect(StatsD).to have_received(:increment).with(
              'api.claims_evidence.upload.failure',
              tags: base_tags + ['error_class:Common::Client::Errors::ClientError',
                                 "document_type_id:#{valid_doc_type_id}"]
            )
          end
        end

        context 'when staging the file fails before the CE call' do
          before do
            file # build the fixture upload before stubbing the copy it relies on
            allow(IO).to receive(:copy_stream).and_raise(Errno::ENOSPC)
          end

          it 'increments the upload failure counter with error_class' do
            allow(StatsD).to receive(:increment).and_call_original
            post_upload
            expect(StatsD).to have_received(:increment).with(
              'api.claims_evidence.upload.failure',
              tags: base_tags + ['error_class:Errno::ENOSPC', "document_type_id:#{valid_doc_type_id}"]
            )
          end
        end

        context 'when param validation fails' do
          it 'does not increment the upload failure counter' do
            allow(StatsD).to receive(:increment).and_call_original
            post_upload(documentTypeId: 999)
            expect(StatsD).not_to have_received(:increment).with(
              'api.claims_evidence.upload.failure', anything
            )
          end
        end
      end
    end
  end
end
