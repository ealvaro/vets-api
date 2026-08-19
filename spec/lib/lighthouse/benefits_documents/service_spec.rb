# frozen_string_literal: true

require 'rails_helper'
require 'lighthouse/benefits_documents/service'
require 'lighthouse_document'
require 'lighthouse/benefits_documents/configuration'

RSpec.describe BenefitsDocuments::Service do
  subject { service }

  let(:user) { create(:user, :loa3) }
  let(:user_account) { create(:user_account) }
  let(:service) { BenefitsDocuments::Service.new(user) }

  before do
    allow_any_instance_of(Auth::ClientCredentials::Service).to receive(:get_token).and_return('fake_access_token')
    user.user_account_uuid = user_account.id
    user.save!
  end

  describe '#queue_document_upload' do
    describe 'when uploading single file' do
      let(:claim_id) { '1' }
      let(:upload_file) do
        f = Tempfile.new(['file with spaces', '.txt'])
        f.write('test')
        f.rewind
        rack_file = Rack::Test::UploadedFile.new(f.path, 'image/jpeg')

        ActionDispatch::Http::UploadedFile.new(
          tempfile: rack_file.tempfile,
          filename: rack_file.original_filename,
          type: rack_file.content_type
        )
      end

      let(:params) do
        {
          file_number: 'xyz',
          claimId: claim_id,
          file: upload_file,
          trackedItemIds: ['1'], # Lighthouse expects an array for tracked items
          documentType: 'L023',
          password: 'password',
          qqfilename: 'test.txt'
        }
      end

      let(:issue_instant) { Time.current.to_i }
      let(:submitted_date) do
        BenefitsDocuments::Utilities::Helpers.format_date_for_mailers(issue_instant)
      end

      before do
        allow_any_instance_of(BenefitsDocuments::Service).to receive(:validate_claimant_can_upload)
          .and_return(true)
      end

      context 'when the document being uploaded is not a duplicate' do
        context 'when cst_synchronous_evidence_uploads is false and cst_send_evidence_submission_failure_emails is true' do # rubocop:disable Layout/LineLength
          before do
            allow(Flipper).to receive(:enabled?).with(:cst_send_evidence_submission_failure_emails)
                                                .and_return(true)
            allow(Flipper).to receive(:enabled?).with(:cst_synchronous_evidence_uploads,
                                                      instance_of(User)).and_return(false)
            allow_any_instance_of(BenefitsDocuments::Service).to receive(:presumed_duplicate?)
              .and_return(false)
            allow(StatsD).to receive(:increment)
            allow(Rails.logger).to receive(:info)
          end

          it 'enqueues a job' do
            expect do
              service.queue_document_upload(params)
            end.to change(Lighthouse::EvidenceSubmissions::DocumentUpload.jobs, :size).by(1)
          end

          it 'records evidence submission with CREATED status' do
            subject.queue_document_upload(params)
            expect(EvidenceSubmission.count).to eq(1)
            evidence_submission = EvidenceSubmission.first
            current_personalisation = JSON.parse(evidence_submission.template_metadata)['personalisation']
            expect(evidence_submission.upload_status)
              .to eql(BenefitsDocuments::Constants::UPLOAD_STATUS[:CREATED])
            expect(current_personalisation['date_submitted']).to eql(submitted_date)
            expect(evidence_submission.tracked_item_id).to be(1)
            expect(evidence_submission.file_size).to eq(File.size(params[:file]))
            expect(StatsD)
              .to have_received(:increment)
              .with('cst.lighthouse.document_uploads.evidence_submission_record_created')
            expect(Rails.logger)
              .to have_received(:info)
              .with('LH - Created Evidence Submission Record', any_args)
            # ensure the logger is filtering out sensitive data
            expect(Rails.logger).to have_received(:info).with(
              a_string_starting_with('Parameters for document upload'),
              hash_including(
                file: have_attributes(
                  content_type: 'image/jpeg',
                  headers: '[FILTERED!]',
                  original_filename: '[FILTERED!]'
                ),
                file_number: 'xyz',
                claimId: '1',
                trackedItemIds: ['1'],
                documentType: 'L023'
              )
            )
            expect(Rails.logger).not_to have_received(:info).with(
              a_string_starting_with('Parameters for document upload'),
              hash_including(
                password: 'password',
                qqfilename: 'test.txt'
              )
            )
          end
        end

        context 'when cst_synchronous_evidence_uploads and cst_send_evidence_submission_failure_emails is disabled' do
          before do
            allow(Flipper).to receive(:enabled?).with(:cst_send_evidence_submission_failure_emails)
                                                .and_return(false)
            allow(Flipper).to receive(:enabled?).with(:cst_synchronous_evidence_uploads,
                                                      instance_of(User)).and_return(false)
          end

          it 'does not record an evidence submission' do
            expect do
              service.queue_document_upload(params)
            end.not_to change(EvidenceSubmission, :count)
          end
        end

        context 'when cst_synchronous_evidence_uploads is true and cst_send_evidence_submission_failure_emails is false' do # rubocop:disable Layout/LineLength
          before do
            allow(Flipper).to receive(:enabled?).with(:cst_send_evidence_submission_failure_emails)
                                                .and_return(false)
            allow(Flipper).to receive(:enabled?).with(:cst_synchronous_evidence_uploads,
                                                      instance_of(User)).and_return(true)
          end

          it 'does not enqueue a job' do
            VCR.use_cassette('lighthouse/benefits_claims/documents/lighthouse_document_upload_200_pdf') do
              expect do
                service.queue_document_upload(params)
              end.not_to change(Lighthouse::EvidenceSubmissions::DocumentUpload.jobs, :size)
              expect(EvidenceSubmission.count).to eq(0)
            end
          end
        end
      end

      context 'when the document being uploaded is a duplicate' do
        let(:evidence_submission) do
          create(:bd_evidence_submission_pending, claim_id:, user_account:)
        end

        let(:upload_file) do
          f = Tempfile.new(['file with spaces', '.txt'])
          f.write('test')
          f.rewind
          rack_file = Rack::Test::UploadedFile.new(f.path, 'image/jpeg')

          ActionDispatch::Http::UploadedFile.new(
            tempfile: rack_file.tempfile,
            filename: JSON.parse(evidence_submission.template_metadata)['personalisation']['file_name'],
            type: rack_file.content_type
          )
        end

        it 'raises an exception' do
          expect do
            subject.queue_document_upload(params)
          end.to raise_error(Common::Exceptions::UnprocessableEntity)
        end
      end

      context 'when the claimant is not allowed to upload documents to the claim' do
        before do
          allow_any_instance_of(BenefitsDocuments::Service).to receive(:validate_claimant_can_upload).and_return(false)
        end

        it 'raises an exception' do
          expect do
            subject.queue_document_upload(params)
          end.to raise_error(Common::Exceptions::UnprocessableEntity)
        end
      end

      context 'when the document being uploaded has an incorrect password' do
        let(:upload_file) do
          f = Tempfile.new(['test_document', '.pdf'])
          f.write('%PDF-1.4 test content')
          f.rewind
          rack_file = Rack::Test::UploadedFile.new(f.path, 'application/pdf')
          ActionDispatch::Http::UploadedFile.new(
            tempfile: rack_file.tempfile,
            filename: rack_file.original_filename,
            type: rack_file.content_type
          )
        end

        shared_examples 'incorrect password error' do
          it 'raises an UnprocessableEntity exception' do
            expect do
              subject.queue_document_upload(params)
            end.to raise_error(Common::Exceptions::UnprocessableEntity) { |error|
              expect(error.errors.first.detail).to eq('DOC_UPLOAD_INCORRECT_PASSWORD')
              expect(error.errors.first.source).to eq('BenefitsDocuments::Service')
            }
          end
        end

        context "when the 'lighthouse_document_convert_to_unlocked_pdf_use_hexapdf' flipper is disabled" do
          before do
            allow(Flipper).to receive(:enabled?)
              .with(:lighthouse_document_convert_to_unlocked_pdf_use_hexapdf)
              .and_return(false)
            allow_any_instance_of(LighthouseDocument).to receive(:unlock_with_pdftk) do |doc, _tempfile|
              doc.errors.add(:base, I18n.t('errors.messages.uploads.pdf.incorrect_password'))
            end
          end

          include_examples 'incorrect password error'
        end

        context "when the 'lighthouse_document_convert_to_unlocked_pdf_use_hexapdf' flipper is enabled" do
          before do
            allow(Flipper).to receive(:enabled?)
              .with(:lighthouse_document_convert_to_unlocked_pdf_use_hexapdf)
              .and_return(true)
            allow_any_instance_of(LighthouseDocument).to receive(:unlock_with_hexapdf) do |doc, _tempfile|
              doc.errors.add(:base, I18n.t('errors.messages.uploads.pdf.incorrect_password'))
            end
          end

          include_examples 'incorrect password error'
        end
      end
    end
  end

  context 'claim letters' do
    describe '#claim_letters_search' do
      it 'receives a list of claim letters' do
        response_body = {
          data: {
            documents: [
              {
                docTypeId: 184,
                subject: 'string',
                documentUuid: '12345678-ABCD-0123-cdef-124345679ABC',
                originalFileName: 'SupportingDocument.pdf',
                documentTypeLabel: 'VA 21-526 Veterans Application for Compensation or Pension',
                trackedItemId: 600_000_001,
                uploadedDateTime: '2016-02-04T17:51:56Z'
              }
            ]
          }
        }

        allow_any_instance_of(Faraday::Connection).to receive(:post)
          .and_return(Faraday::Response.new(
                        status: 200, body: response_body
                      ))
        expect_any_instance_of(BenefitsDocuments::Configuration)
          .to(receive(:claim_letters_search).once.and_call_original)

        response = subject.claim_letters_search(file_number: user.ssn)

        expect(response.body.as_json['data']['documents'][0]['docTypeId']).to eq(184)
      end
    end

    describe '#claim_letters_search failure logging' do
      let(:faraday_error) { Faraday::ClientError.new('Bad Request') }

      before do
        allow_any_instance_of(BenefitsDocuments::Configuration)
          .to receive(:claim_letters_search).and_raise(faraday_error)
        allow(Rails.logger).to receive(:info)
        allow(user).to receive_messages(veteran?: true, served_in_military?: true, birls_id: '796104437',
                                        veteran_status: double(title38_status: 'V1'))
      end

      context 'when cst_claim_letters_log_failure is enabled' do
        before do
          allow(Flipper).to receive(:enabled?).with(:cst_claim_letters_log_failure, user).and_return(true)
        end

        it 'logs the failure with doc_type_ids and presence of participant_id and file_number' do
          expect(Rails.logger).to receive(:info).with(
            'Claim letters failure for user',
            hash_including(
              message_type: 'cst.claim_letters.search_failure',
              doc_type_ids: ['184'],
              participant_id_present: false,
              file_number_present: true,
              title38_status: 'V1',
              birls_id_present: true,
              error_type: 'Faraday::ClientError',
              error_message: 'Bad Request'
            )
          )

          expect { subject.claim_letters_search(doc_type_ids: ['184'], file_number: user.ssn) }
            .to raise_error(Common::Exceptions::ServiceError)
        end

        it "logs nil title38_status when 'VAProfile::VeteranStatus::Service#get_veteran_status' raises" do
          allow(user).to receive(:veteran_status).and_raise(StandardError)

          expect(Rails.logger).to receive(:info).with(
            'Claim letters failure for user',
            hash_including(title38_status: nil)
          )

          expect { subject.claim_letters_search(doc_type_ids: ['184'], file_number: user.ssn) }
            .to raise_error(Common::Exceptions::ServiceError)
        end

        it 'logs birls_id_present as false when the MPI-backed birls_id lookup raises an exception' do
          allow(user).to receive(:birls_id).and_raise(StandardError)

          expect(Rails.logger).to receive(:info).with(
            'Claim letters failure for user',
            hash_including(birls_id_present: false)
          )

          expect { subject.claim_letters_search(doc_type_ids: ['184'], file_number: user.ssn) }
            .to raise_error(Common::Exceptions::ServiceError)
        end

        it 'logs participant_id_present as true when provided' do
          expect(Rails.logger).to receive(:info).with(
            'Claim letters failure for user',
            hash_including(
              participant_id_present: true,
              file_number_present: false
            )
          )

          expect { subject.claim_letters_search(doc_type_ids: ['184'], participant_id: '12345') }
            .to raise_error(Common::Exceptions::ServiceError)
        end
      end

      context 'when cst_claim_letters_log_failure is disabled' do
        before do
          allow(Flipper).to receive(:enabled?).with(:cst_claim_letters_log_failure, user).and_return(false)
        end

        it 'does not log the failure' do
          expect(Rails.logger).not_to receive(:info).with('Claim letters failure for user', anything)

          expect { subject.claim_letters_search(file_number: user.ssn) }
            .to raise_error(Common::Exceptions::ServiceError)
        end
      end
    end

    describe '#claim_letters_search success metric' do
      let(:response_body) { { data: { documents: [{ docTypeId: 184 }] } } }

      before do
        allow_any_instance_of(BenefitsDocuments::Configuration)
          .to receive(:claim_letters_search)
          .and_return(Faraday::Response.new(status: 200, body: response_body))
        allow(StatsD).to receive(:increment)
        allow(user).to receive_messages(veteran?: false, served_in_military?: true, birls_id: '796104437',
                                        veteran_status: double(title38_status: 'V4'))
      end

      it 'increments the success counter tagged with the user-state field values' do
        subject.claim_letters_search(file_number: user.ssn)

        expect(StatsD).to have_received(:increment).with(
          'cst.claim_letters.search_success',
          tags: array_including('title38_status:V4', 'birls_id_present:true', 'is_veteran:false',
                                'served_in_military:true')
        )
      end

      it 'tags title38_status as none when "VAProfile::VeteranStatus::Service#get_veteran_status" raises' do
        allow(user).to receive(:veteran_status).and_raise(StandardError)

        subject.claim_letters_search(file_number: user.ssn)

        expect(StatsD).to have_received(:increment).with(
          'cst.claim_letters.search_success',
          tags: array_including('title38_status:none')
        )
      end

      context 'when building the success metric raises' do
        before do
          allow(user).to receive(:veteran?).and_raise(StandardError.new('VA Profile down'))
        end

        it 'returns the response and never raises' do
          response = nil
          expect { response = subject.claim_letters_search(file_number: user.ssn) }.not_to raise_error
          expect(response.status).to eq(200)
        end

        it 'increments the failure counter tagged with the error class' do
          subject.claim_letters_search(file_number: user.ssn)

          expect(StatsD).to have_received(:increment).with(
            'cst.claim_letters.search_success_metric_error',
            tags: ['error_class:StandardError']
          )
        end
      end
    end

    describe '#claim_letter_download' do
      it 'receives content of a claim letter pdf' do
        response_body = 'claim letter pdf file content'

        allow_any_instance_of(Faraday::Connection).to receive(:post)
          .and_return(Faraday::Response.new(
                        status: 200, body: response_body
                      ))
        expect_any_instance_of(BenefitsDocuments::Configuration)
          .to(receive(:claim_letter_download).once.and_call_original)

        response = subject.claim_letter_download(document_uuid: 'a-required-uuid', file_number: user.ssn)

        expect(response.body).to eq(response_body)
      end
    end
  end

  context 'participant documents' do
    describe '#participant_documents_search' do
      it 'receives a list of participant documents' do
        response_body = {
          data: {
            documents: [
              {
                docTypeId: 137,
                subject: 'File contains evidence related to the claim',
                documentUuid: '{12345678-ABCD-0123-cdef-124345679ABC}',
                originalFileName: 'SupportingDocument.pdf',
                documentTypeLabel: 'VA 21-526 Veterans Application for Compensation or Pension',
                uploadedDateTime: '2016-02-04T17:51:56Z',
                receivedAt: '2016-02-04'
              }
            ]
          },
          pagination: {
            pageNumber: 1,
            pageSize: 25
          }
        }

        allow_any_instance_of(Faraday::Connection).to receive(:post)
          .and_return(Faraday::Response.new(
                        status: 200, body: response_body
                      ))
        expect_any_instance_of(BenefitsDocuments::Configuration)
          .to(receive(:participant_documents_search).once.and_call_original)

        response = subject.participant_documents_search(participant_id: user.participant_id)

        expect(response.body.as_json['data']['documents'][0]['docTypeId']).to eq(137)
        expect(response.body.as_json['data']['documents'][0]['subject'])
          .to eq('File contains evidence related to the claim')
        expect(response.body.as_json['pagination']['pageNumber']).to eq(1)
        expect(response.body.as_json['pagination']['pageSize']).to eq(25)
      end

      it 'receives a list of participant documents with custom pagination' do
        response_body = {
          data: {
            documents: []
          },
          pagination: {
            pageNumber: 2,
            pageSize: 50
          }
        }

        allow_any_instance_of(Faraday::Connection).to receive(:post)
          .and_return(Faraday::Response.new(
                        status: 200, body: response_body
                      ))
        expect_any_instance_of(BenefitsDocuments::Configuration)
          .to(receive(:participant_documents_search).with(
            participant_id: user.participant_id,
            page_number: 2,
            page_size: 50
          ).once.and_call_original)

        response = subject.participant_documents_search(
          participant_id: user.participant_id,
          page_number: 2,
          page_size: 50
        )

        expect(response.body.as_json['pagination']['pageNumber']).to eq(2)
        expect(response.body.as_json['pagination']['pageSize']).to eq(50)
      end

      it 'handles error responses' do
        error_response = Faraday::ServerError.new(
          'status' => 500,
          'response_body' => { 'error' => 'Internal Server Error' }
        )

        allow_any_instance_of(BenefitsDocuments::Configuration)
          .to receive(:participant_documents_search).and_raise(error_response)

        expect(Lighthouse::ServiceException)
          .to receive(:send_error).with(
            error_response,
            'benefits_documents/service',
            nil,
            %r{services/benefits-documents/v1/participant/documents/search}
          ).and_raise(Common::Exceptions::ExternalServerInternalServerError)

        expect do
          subject.participant_documents_search(participant_id: user.participant_id)
        end.to raise_error(Common::Exceptions::ExternalServerInternalServerError)
      end
    end

    describe '#participant_documents_download' do
      it 'receives content of a participant document pdf' do
        response_body = 'participant document pdf file content'

        allow_any_instance_of(Faraday::Connection).to receive(:post)
          .and_return(Faraday::Response.new(
                        status: 200, body: response_body
                      ))
        expect_any_instance_of(BenefitsDocuments::Configuration)
          .to(receive(:participant_documents_download).once.and_call_original)

        response = subject.participant_documents_download(
          document_uuid: '{12345678-ABCD-0123-cdef-124345679ABC}',
          participant_id: user.participant_id
        )

        expect(response.body).to eq(response_body)
      end

      it 'receives content of a participant document pdf with file_number' do
        response_body = 'participant document pdf file content'

        allow_any_instance_of(Faraday::Connection).to receive(:post)
          .and_return(Faraday::Response.new(
                        status: 200, body: response_body
                      ))
        expect_any_instance_of(BenefitsDocuments::Configuration)
          .to(receive(:participant_documents_download).with(
            document_uuid: '{12345678-ABCD-0123-cdef-124345679ABC}',
            participant_id: nil,
            file_number: user.ssn
          ).once.and_call_original)

        response = subject.participant_documents_download(
          document_uuid: '{12345678-ABCD-0123-cdef-124345679ABC}',
          file_number: user.ssn
        )

        expect(response.body).to eq(response_body)
      end

      it 'handles error responses with json body' do
        error_body = {
          errors: [
            {
              status: '404',
              title: 'Resource Not Found',
              detail: 'Document not found'
            }
          ]
        }

        allow_any_instance_of(Faraday::Connection).to receive(:post)
          .and_return(Faraday::Response.new(
                        status: 404, body: error_body
                      ))

        error_response = Faraday::ClientError.new(
          'status' => 404,
          'response_body' => error_body
        )

        allow_any_instance_of(BenefitsDocuments::Configuration)
          .to receive(:participant_documents_download).and_raise(error_response)

        expect(Lighthouse::ServiceException)
          .to receive(:send_error).with(
            error_response,
            'benefits_documents/service',
            nil,
            %r{services/benefits-documents/v1/participant/documents/download}
          ).and_raise(Common::Exceptions::ResourceNotFound)

        expect do
          subject.participant_documents_download(
            document_uuid: '{12345678-ABCD-0123-cdef-124345679ABC}',
            participant_id: user.participant_id
          )
        end.to raise_error(Common::Exceptions::ResourceNotFound)
      end
    end
  end

  describe '#create_personalisation' do
    let(:document) do
      instance_double(LighthouseDocument,
                      first_name:,
                      description: 'Copy of a DD214',
                      file_name: 'doctors-note.pdf')
    end

    context 'when the first name is all caps' do
      let(:first_name) { 'VANESSA' }

      it 'titlecases the name without splitting on inflection acronyms' do
        expect(service.send(:create_personalisation, document)[:first_name]).to eq('Vanessa')
      end
    end

    context 'when the first name is all caps and hyphenated' do
      let(:first_name) { 'ANNE-MARIE' }

      it 'preserves the hyphen' do
        expect(service.send(:create_personalisation, document)[:first_name]).to eq('Anne-Marie')
      end
    end

    context 'when the first name is missing' do
      let(:first_name) { nil }

      it 'returns a nil first name' do
        expect(service.send(:create_personalisation, document)[:first_name]).to be_nil
      end
    end
  end
end
