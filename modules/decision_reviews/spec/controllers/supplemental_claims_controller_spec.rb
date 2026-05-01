# frozen_string_literal: true

require './modules/decision_reviews/spec/dr_spec_helper'
require './modules/decision_reviews/spec/support/vcr_helper'

RSpec.describe DecisionReviews::V1::SupplementalClaimsController, type: :controller do
  routes { DecisionReviews::Engine.routes }

  let(:user) { build(:user, :loa3) }
  let(:uuid) { SecureRandom.uuid }

  before do
    sign_in_as(user)
  end

  describe '#show' do
    let(:service) { instance_double(DecisionReviews::V1::Service) }
    let(:response_body) { { 'data' => { 'id' => uuid, 'type' => 'supplementalClaim' } } }
    let(:faraday_response) { double(body: response_body) }

    before do
      allow(controller).to receive(:decision_review_service).and_return(service)
    end

    context 'when successful' do
      it 'returns the supplemental claim' do
        allow(service).to receive(:get_supplemental_claim).with(uuid).and_return(faraday_response)

        get :show, params: { id: uuid }

        expect(response).to have_http_status(:ok)
        expect(JSON.parse(response.body)).to eq(response_body)
      end
    end

    context 'when an error occurs' do
      before do
        bypass_rescue
      end

      it 'logs the error to personal information log and re-raises' do
        error = StandardError.new('Service error')
        allow(service).to receive(:get_supplemental_claim).with(uuid).and_raise(error)
        allow(controller).to receive(:log_exception_to_personal_information_log)

        expect { get :show, params: { id: uuid } }.to raise_error(StandardError, 'Service error')

        expect(controller).to have_received(:log_exception_to_personal_information_log).with(
          error,
          error_class: 'DecisionReviews::V1::SupplementalClaimsController#show exception StandardError (SC_V1)',
          id: uuid
        )
      end
    end
  end

  describe '#create' do
    let(:service) { instance_double(DecisionReviews::V1::Service) }
    let(:normalizer) { instance_double(DecisionReviews::V1::SupplementalClaims::RequestBodyNormalizer) }
    let(:request_body) do
      {
        'data' => {
          'attributes' => {
            'veteran' => {
              'address' => {
                'zipCode5' => '12345'
              }
            }
          }
        }
      }
    end
    let(:normalized_body) { request_body.deep_dup }
    let(:sc_response_body) { { 'data' => { 'id' => uuid } } }
    let(:sc_response) { double(body: sc_response_body, status: 200) }
    let(:appeal_submission) { double(id: 123) }

    before do
      allow(controller).to receive_messages(decision_review_service: service, request_body_hash: request_body)
      allow(DecisionReviews::V1::SupplementalClaims::RequestBodyNormalizer).to receive(:new)
        .with(request_body).and_return(normalizer)
      allow(normalizer).to receive(:normalize).and_return(normalized_body)
      allow(service).to receive(:create_supplemental_claim).and_return(sc_response)
      allow(DecisionReviews::V1::Service).to receive(:file_upload_metadata).and_return({})
      allow(AppealSubmission).to receive(:create!).and_return(appeal_submission)
      allow(controller).to receive(:store_saved_claim)
      allow(InProgressForm).to receive(:form_for_user).with(anything, anything).and_return(nil)
    end

    context 'basic submission without form4142 or evidence' do
      it 'creates a supplemental claim successfully' do
        allow(Rails.logger).to receive(:info)

        post :create

        expect(response).to have_http_status(:ok)
        expect(JSON.parse(response.body)).to eq(sc_response_body)
        expect(Rails.logger).to have_received(:info).with(hash_including(
                                                            message: 'Supplemental Claim Appeal Record Created',
                                                            appeal_submission_id: 123,
                                                            lighthouse_submission: { id: uuid }
                                                          ))
      end

      it 'destroys the in-progress form' do
        in_progress_form = double
        allow(InProgressForm).to receive(:form_for_user).with('20-0995', anything).and_return(in_progress_form)
        allow(in_progress_form).to receive(:destroy!)
        allow(Rails.logger).to receive(:info)

        post :create

        expect(in_progress_form).to have_received(:destroy!)
      end
    end

    context 'with form4142' do
      let(:form4142_data) { { 'limitedConsent' => 'test' } }
      let(:normalized_body) do
        request_body.deep_dup.merge('form4142' => form4142_data)
      end
      let(:rejiggered_payload) { { 'rejiggered' => true } }
      let(:job_id) { 'job-123' }

      before do
        allow(controller).to receive(:get_and_rejigger_required_info).and_return(rejiggered_payload)
        allow(service).to receive(:queue_form4142).and_return(job_id)
        allow(Rails.logger).to receive(:info)
      end

      it 'queues form4142 submission and logs it' do
        post :create

        expect(service).to have_received(:queue_form4142).with(
          appeal_submission_id: 123,
          rejiggered_payload:,
          submitted_appeal_uuid: uuid
        )

        expect(Rails.logger).to have_received(:info).with(hash_including(
                                                            form_id: '4142',
                                                            parent_form_id: '20-0995',
                                                            message: 'Supplemental Claim Form4142 queued.',
                                                            jid: job_id
                                                          ))
      end
    end

    context 'with evidence' do
      let(:evidence_data) { [{ 'name' => 'evidence.pdf' }] }
      let(:normalized_body) do
        request_body.deep_dup.merge('additionalDocuments' => evidence_data)
      end
      let(:evidence_job_ids) { %w[evidence-job-1 evidence-job-2] }

      before do
        allow(service).to receive(:queue_submit_evidence_uploads).and_return(evidence_job_ids)
        allow(Rails.logger).to receive(:info)
      end

      it 'queues evidence uploads and logs them' do
        post :create

        expect(service).to have_received(:queue_submit_evidence_uploads).with(evidence_data, 123)

        expect(Rails.logger).to have_received(:info).with(hash_including(
                                                            form_id: '20-0995',
                                                            message: 'Supplemental Claim Evidence jobs created.',
                                                            evidence_upload_job_ids: evidence_job_ids
                                                          ))
      end
    end

    context 'when an error occurs' do
      let(:error) { StandardError.new('Submission failed') }

      before do
        bypass_rescue
        allow(service).to receive(:create_supplemental_claim).and_raise(error)
        allow(Rails.logger).to receive(:error)
        allow(controller).to receive(:log_exception_to_personal_information_log)
      end

      it 'logs the error message and re-raises' do
        expect { post :create }.to raise_error(StandardError, 'Submission failed')

        expect(Rails.logger).to have_received(:error).with(
          hash_including(
            message: 'Exception occurred while submitting Supplemental Claim: Submission failed'
          )
        )
      end

      it 'logs to personal information log and re-raises' do
        expect { post :create }.to raise_error(StandardError, 'Submission failed')

        expect(controller).to have_received(:log_exception_to_personal_information_log).with(
          error,
          error_class: 'DecisionReviews::V1::SupplementalClaimsController#create exception StandardError (SC_V1)',
          request: { body: request_body }
        )
      end

      context 'when request_body_hash fails' do
        before do
          allow(controller).to receive(:request_body_hash).and_raise(JSON::ParserError)
          allow(controller).to receive(:request_body_debug_data).and_return({ debug: 'data' })
        end

        it 'uses request_body_debug_data for logging and re-raises' do
          expect { post :create }.to raise_error(JSON::ParserError)

          expect(controller).to have_received(:log_exception_to_personal_information_log).with(
            instance_of(JSON::ParserError),
            error_class: 'DecisionReviews::V1::SupplementalClaimsController#create exception JSON::ParserError (SC_V1)',
            request: { debug: 'data' }
          )
        end
      end
    end
  end

  describe '#process_submission' do
    it 'delegates to RequestBodyNormalizer for schema transformations' do
      normalizer_double = instance_double(DecisionReviews::V1::SupplementalClaims::RequestBodyNormalizer)
      allow(DecisionReviews::V1::SupplementalClaims::RequestBodyNormalizer).to receive(:new)
        .and_return(normalizer_double)
      allow(normalizer_double).to receive(:normalize).and_return({
                                                                   'data' => { 'attributes' => {} },
                                                                   'form4142' => nil,
                                                                   'additionalDocuments' => nil
                                                                 })

      # We're testing that the normalizer is called, not the full submission flow
      expect(DecisionReviews::V1::SupplementalClaims::RequestBodyNormalizer).to receive(:new)
        .with(anything)
      expect(normalizer_double).to receive(:normalize)

      # Stub the rest of the submission flow so the method can complete without masking errors
      allow(controller).to receive_messages(request_body_hash: {},
                                            decision_review_service: double(create_supplemental_claim: double(body: { 'data' => { 'id' => 'test-uuid' } }, status: 200))) # rubocop:disable Layout/LineLength
      allow(controller).to receive(:create_appeal_submission).and_return(1)
      allow(AppealSubmission).to receive(:create!).and_return(double(id: 1))
      allow(controller).to receive(:store_saved_claim)
      allow(controller).to receive(:clear_in_progress_form)
      allow(controller).to receive(:render)
      allow(InProgressForm).to receive(:form_for_user).and_return(nil)
      allow(DecisionReviews::V1::Service).to receive(:file_upload_metadata).and_return({})
      allow(ActiveRecord::Base).to receive(:transaction).and_yield

      controller.send(:process_submission)
    end
  end

  describe 'private methods' do
    describe '#create_appeal_submission' do
      let(:upload_metadata) { { 'file' => 'metadata' } }
      let(:appeal_submission) { double(id: 456) }

      before do
        # Set @current_user for the controller instance
        controller.instance_variable_set(:@current_user, user)
        allow(DecisionReviews::V1::Service).to receive(:file_upload_metadata)
          .with(user, '12345').and_return(upload_metadata)
        allow(AppealSubmission).to receive(:create!).and_return(appeal_submission)
      end

      it 'creates an appeal submission with correct params' do
        allow(AppealSubmission).to receive(:create!).with(
          user_account: user.user_account,
          type_of_appeal: 'SC',
          submitted_appeal_uuid: uuid,
          upload_metadata:
        ).and_return(appeal_submission)

        result = controller.send(:create_appeal_submission, uuid, '12345')

        expect(result).to eq(456)
        expect(AppealSubmission).to have_received(:create!).with(
          user_account: user.user_account,
          type_of_appeal: 'SC',
          submitted_appeal_uuid: uuid,
          upload_metadata:
        )
      end
    end

    describe '#handle_saved_claim' do
      let(:form_data) { '{"test": "data"}' }
      let(:guid) { 'test-guid' }

      before do
        allow(controller).to receive(:store_saved_claim)
      end

      it 'stores saved claim without form4142' do
        controller.send(:handle_saved_claim, form: form_data, guid:, form4142: nil)

        expect(controller).to have_received(:store_saved_claim).with(
          claim_class: SavedClaim::SupplementalClaim,
          form: form_data,
          guid:,
          uploaded_forms: []
        )
      end

      it 'stores saved claim with form4142' do
        controller.send(:handle_saved_claim, form: form_data, guid:, form4142: { 'data' => 'test' })

        expect(controller).to have_received(:store_saved_claim).with(
          claim_class: SavedClaim::SupplementalClaim,
          form: form_data,
          guid:,
          uploaded_forms: ['21-4142']
        )
      end
    end

    describe '#error_class' do
      it 'generates correct error class string' do
        result = controller.send(:error_class, method: 'test_method', exception_class: ArgumentError)
        expected_string = 'DecisionReviews::V1::SupplementalClaimsController#test_method ' \
                          'exception ArgumentError (SC_V1)'
        expect(result).to eq(expected_string)
      end
    end
  end
end
