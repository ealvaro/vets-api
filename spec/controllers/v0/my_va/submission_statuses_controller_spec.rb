# frozen_string_literal: true

require 'rails_helper'

RSpec.describe V0::MyVA::SubmissionStatusesController, type: :controller do
  let(:user) { build(:user, :loa3) }
  let(:user_account) { user.user_account }

  before do
    sign_in_as(user)
    allow(Flipper).to receive(:enabled?)
      .with(:benefits_claims_ivc_champva_provider, instance_of(User)).and_return(false)
  end

  describe 'GET #show' do
    context 'when both feature flags are disabled' do
      let(:empty_report) do
        double('Report', submission_statuses: [], errors: [])
      end

      before do
        allow(Flipper).to receive(:enabled?)
                      .with(:my_va_display_all_lighthouse_benefits_intake_forms, instance_of(User)).and_return(false)
        allow(Flipper).to receive(:enabled?)
                      .with(:my_va_display_decision_reviews_forms, instance_of(User)).and_return(false)
        allow(Flipper).to receive(:enabled?).with(:hca_status_card_enabled, instance_of(User)).and_return(false)
      end

      it 'returns empty array when no forms are allowed' do
        get :show

        expect(response).to have_http_status(:ok)
        json_response = JSON.parse(response.body)
        expect(json_response['data']).to eq([])
      end
    end

    context 'when benefits intake flag is enabled but decision reviews is disabled' do
      let(:benefits_report) do
        double('Report', submission_statuses: [], errors: [])
      end

      before do
        allow(Flipper).to receive(:enabled?).with(:my_va_display_all_lighthouse_benefits_intake_forms,
                                                  instance_of(User)).and_return(true)
        allow(Flipper).to receive(:enabled?).with(:my_va_display_decision_reviews_forms,
                                                  instance_of(User)).and_return(false)

        allow(Flipper).to receive(:enabled?).with(:hca_status_card_enabled, instance_of(User)).and_return(false)
      end

      it 'creates report with only benefits intake enabled' do
        allow(Forms::SubmissionStatuses::Report).to receive(:new).and_return(benefits_report)
        allow(benefits_report).to receive(:run).and_return(benefits_report)

        get :show

        expect(response).to have_http_status(:ok)

        # Verify the report was created and run
        expect(Forms::SubmissionStatuses::Report).to have_received(:new).with(
          user_account: anything,
          allowed_forms: nil,
          gateway_options: anything
        )
        expect(benefits_report).to have_received(:run)
      end
    end

    context 'when only the health care applications flag is enabled' do
      let(:benefits_report) do
        double('Report', submission_statuses: [], errors: [])
      end

      before do
        allow(Flipper).to receive(:enabled?).with(:my_va_display_all_lighthouse_benefits_intake_forms,
                                                  instance_of(User)).and_return(false)
        allow(Flipper).to receive(:enabled?).with(:my_va_display_decision_reviews_forms,
                                                  instance_of(User)).and_return(false)

        allow(Flipper).to receive(:enabled?).with(:hca_status_card_enabled, instance_of(User)).and_return(true)
      end

      it 'creates report with only HCA forms enabled' do
        allow(Forms::SubmissionStatuses::Report).to receive(:new).and_return(benefits_report)
        allow(benefits_report).to receive(:run).and_return(benefits_report)

        get :show

        expect(response).to have_http_status(:ok)

        # Verify the report was created and run
        expect(Forms::SubmissionStatuses::Report).to have_received(:new).with(
          user_account: anything,
          allowed_forms: array_including('1010ez'),
          gateway_options: anything
        )
        expect(benefits_report).to have_received(:run)
      end
    end

    context 'when decision reviews flag is enabled but benefits intake is disabled' do
      let(:decision_reviews_report) do
        double('Report', submission_statuses: [], errors: [])
      end

      before do
        allow(Flipper).to receive(:enabled?).with(:my_va_display_all_lighthouse_benefits_intake_forms,
                                                  instance_of(User)).and_return(false)
        allow(Flipper).to receive(:enabled?).with(:my_va_display_decision_reviews_forms,
                                                  instance_of(User)).and_return(true)
        allow(Flipper).to receive(:enabled?).with(:hca_status_card_enabled, instance_of(User)).and_return(false)
      end

      it 'creates report with only decision reviews enabled' do
        allow(Forms::SubmissionStatuses::Report).to receive(:new).and_return(decision_reviews_report)
        allow(decision_reviews_report).to receive(:run).and_return(decision_reviews_report)

        get :show

        expect(response).to have_http_status(:ok)

        # Verify the report was created and run
        expect(Forms::SubmissionStatuses::Report).to have_received(:new).with(
          user_account: anything,
          allowed_forms: array_including('20-0995'),
          gateway_options: anything
        )
        expect(decision_reviews_report).to have_received(:run)
      end
    end

    context 'when both feature flags are enabled' do
      let(:combined_report) do
        double(
          'Report',
          submission_statuses: [
            OpenStruct.new(
              id: '123',
              form_type: '21-4142',
              status: 'received',
              message: 'Form received',
              detail: 'Processing started',
              updated_at: 1.day.ago,
              created_at: 2.days.ago,
              pdf_support: true
            )
          ],
          errors: []
        )
      end

      before do
        allow(Flipper).to receive(:enabled?).with(:my_va_display_all_lighthouse_benefits_intake_forms,
                                                  instance_of(User)).and_return(true)
        allow(Flipper).to receive(:enabled?).with(:my_va_display_decision_reviews_forms,
                                                  instance_of(User)).and_return(true)
        allow(Flipper).to receive(:enabled?).with(:hca_status_card_enabled, instance_of(User)).and_return(false)
      end

      it 'creates report with both gateways enabled and all form types' do
        allow(Forms::SubmissionStatuses::Report).to receive(:new).and_return(combined_report)
        allow(combined_report).to receive(:run).and_return(combined_report)

        get :show

        expect(response).to have_http_status(:ok)
        json_response = JSON.parse(response.body)
        expect(json_response['data']).to be_an(Array)
        expect(json_response['data'].length).to eq(1)

        form_data = json_response['data'].first
        expect(form_data['id']).to eq('123')
        expect(form_data['attributes']['form_type']).to eq('21-4142')
        expect(form_data['attributes']['status']).to eq('received')
        expect(form_data['attributes']['pdf_support']).to be true

        # Verify the report was created and run
        expect(Forms::SubmissionStatuses::Report).to have_received(:new).with(
          user_account: anything,
          allowed_forms: nil,
          gateway_options: anything
        )
        expect(combined_report).to have_received(:run)
      end
    end

    context 'gateway options for CHAMPVA email' do
      let(:email_options_report) do
        double('Report', submission_statuses: [], errors: [])
      end

      before do
        allow(Flipper).to receive(:enabled?).with(:my_va_display_all_lighthouse_benefits_intake_forms,
                                                  instance_of(User)).and_return(true)
        allow(Flipper).to receive(:enabled?).with(:my_va_display_decision_reviews_forms,
                                                  instance_of(User)).and_return(false)
        allow(Flipper).to receive(:enabled?).with(:hca_status_card_enabled, instance_of(User)).and_return(false)
        allow(Forms::SubmissionStatuses::Report).to receive(:new).and_return(email_options_report)
        allow(email_options_report).to receive(:run).and_return(email_options_report)
      end

      it 'omits user_email when CHAMPVA flag is disabled' do
        allow(Flipper).to receive(:enabled?)
          .with(:benefits_claims_ivc_champva_provider, anything).and_return(false)

        get :show

        expect(Forms::SubmissionStatuses::Report).to have_received(:new) do |args|
          gateway_options = args[:gateway_options]

          expect(gateway_options[:ivc_champva_enabled]).to be(false)
          expect(gateway_options).not_to have_key(:user_email)
        end
      end

      it 'includes user_email when CHAMPVA flag is enabled' do
        allow(Flipper).to receive(:enabled?)
          .with(:benefits_claims_ivc_champva_provider, anything).and_return(true)

        get :show

        expect(Forms::SubmissionStatuses::Report).to have_received(:new) do |args|
          gateway_options = args[:gateway_options]

          expect(gateway_options[:ivc_champva_enabled]).to be(true)
          expect(gateway_options[:user_email]).to eq(user.email)
        end
      end
    end

    context 'when report execution fails' do
      let(:failing_report) do
        double('Report')
      end

      before do
        allow(Flipper).to receive(:enabled?).with(:my_va_display_all_lighthouse_benefits_intake_forms,
                                                  instance_of(User)).and_return(true)
        allow(Flipper).to receive(:enabled?).with(:my_va_display_decision_reviews_forms,
                                                  instance_of(User)).and_return(false)
        allow(Flipper).to receive(:enabled?).with(:hca_status_card_enabled, instance_of(User)).and_return(false)
        allow(Forms::SubmissionStatuses::Report).to receive(:new).and_return(failing_report)
        allow(failing_report).to receive(:run).and_raise(StandardError, 'Service unavailable')
      end

      it 'handles errors gracefully' do
        # Check if the controller catches and handles the error
        get :show

        # If it doesn't raise an error, it should return a 500 status
        expect(response).to have_http_status(:internal_server_error)
      end
    end

    context 'when feature flag is disabled (restricted list)' do
      it 'includes multi-party form IDs in the restricted benefits intake forms' do
        forms = controller.send(:restricted_benefits_intake_forms)

        expect(forms).to include('21-2680', '21-0779', '21-4192', '21P-530a', '21-4138')
      end
    end

    context 'serialization' do
      let(:mock_submission_status) do
        OpenStruct.new(
          id: 'test-guid-123',
          form_type: '21-4142',
          status: 'processing',
          message: 'Your form is being processed',
          detail: 'Expected completion in 5-7 business days',
          updated_at: Time.zone.parse('2024-01-15T10:30:00Z'),
          created_at: Time.zone.parse('2024-01-10T09:00:00Z'),
          pdf_support: true
        )
      end

      let(:serialization_report) do
        double(
          'Report',
          submission_statuses: [mock_submission_status],
          errors: []
        )
      end

      before do
        allow(Flipper).to receive(:enabled?).with(:my_va_display_all_lighthouse_benefits_intake_forms,
                                                  instance_of(User)).and_return(true)
        allow(Flipper).to receive(:enabled?).with(:my_va_display_decision_reviews_forms,
                                                  instance_of(User)).and_return(false)
        allow(Flipper).to receive(:enabled?).with(:hca_status_card_enabled, instance_of(User)).and_return(false)
        allow(Forms::SubmissionStatuses::Report).to receive(:new).and_return(serialization_report)
        allow(serialization_report).to receive(:run).and_return(serialization_report)
      end

      it 'serializes submission status data correctly' do
        get :show

        expect(response).to have_http_status(:ok)
        json_response = JSON.parse(response.body)

        expect(json_response['data']).to be_an(Array)
        expect(json_response['data'].length).to eq(1)

        serialized_status = json_response['data'].first
        expect(serialized_status['id']).to eq('test-guid-123')
        expect(serialized_status['type']).to eq('submission_status')

        attributes = serialized_status['attributes']
        expect(attributes['form_type']).to eq('21-4142')
        expect(attributes['status']).to eq('processing')
        expect(attributes['message']).to eq('Your form is being processed')
        expect(attributes['detail']).to eq('Expected completion in 5-7 business days')
        expect(attributes['pdf_support']).to be true
        expect(attributes['updated_at']).to eq('2024-01-15T10:30:00.000Z')
        expect(attributes['created_at']).to eq('2024-01-10T09:00:00.000Z')
      end
    end

    context 'StatsD and logging for response status' do
      let(:flipper_defaults) do
        allow(Flipper).to receive(:enabled?).with(:my_va_display_all_lighthouse_benefits_intake_forms,
                                                  instance_of(User)).and_return(true)
        allow(Flipper).to receive(:enabled?).with(:my_va_display_decision_reviews_forms,
                                                  instance_of(User)).and_return(false)
        allow(Flipper).to receive(:enabled?).with(:hca_status_card_enabled, instance_of(User)).and_return(false)
      end

      context 'when response is 200' do
        let(:success_report) { double('Report', submission_statuses: [], errors: []) }

        before do
          flipper_defaults
          allow(Forms::SubmissionStatuses::Report).to receive(:new).and_return(success_report)
          allow(success_report).to receive(:run).and_return(success_report)
        end

        it 'emits a StatsD counter with status:200' do
          expect(StatsD).to receive(:increment).with(
            'api.forms.submission_statuses.response',
            tags: ['status:200']
          )

          get :show
        end

        it 'does not log a partial success warning' do
          allow(StatsD).to receive(:increment)
          expect(Rails.logger).not_to receive(:warn).with('Submission statuses partial success (296)', anything)

          get :show
        end
      end

      context 'when response is 296' do
        let(:partial_report) do
          double(
            'Report',
            submission_statuses: [OpenStruct.new(id: '1', form_type: '21-4142', status: 'received')],
            errors: [{ status: 500, source: 'benefits_intake', title: 'Error', detail: 'fail' }]
          )
        end

        before do
          flipper_defaults
          allow(Forms::SubmissionStatuses::Report).to receive(:new).and_return(partial_report)
          allow(partial_report).to receive(:run).and_return(partial_report)
        end

        it 'emits a StatsD counter with status:296' do
          expect(StatsD).to receive(:increment).with(
            'api.forms.submission_statuses.response',
            tags: ['status:296']
          )

          get :show
        end

        it 'logs a structured summary of the partial success' do
          allow(StatsD).to receive(:increment)
          expect(Rails.logger).to receive(:warn).with(
            'Submission statuses partial success (296)',
            hash_including(
              failed_gateways: ['benefits_intake'],
              total_errors: 1,
              total_submissions: 1
            )
          )

          get :show
        end
      end
    end
  end
end
