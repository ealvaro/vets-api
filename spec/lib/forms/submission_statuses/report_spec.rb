# frozen_string_literal: true

require 'rails_helper'
require 'forms/submission_statuses/gateways/benefits_intake_gateway'
require 'forms/submission_statuses/report'

describe Forms::SubmissionStatuses::Report, feature: :form_submission,
                                            team_owner: :vfs_authenticated_experience_backend do
  subject { described_class.new(user_account:, allowed_forms:) }

  let(:user_account) { create(:user_account) }
  let(:allowed_forms) { %w[20-10207 21-0845 21-0972 21-10210 21-4138 21-4142 21-4142a 21P-0847 21-4140 21P-530EZ] }
  let(:benefits_intake_service) { instance_double(BenefitsIntake::Service) }
  let(:benefits_intake_gateway) { Forms::SubmissionStatuses::Gateways::BenefitsIntakeGateway }

  context 'when user has no submissions' do
    before do
      allow_any_instance_of(benefits_intake_gateway).to receive(:submissions).and_return([])
      allow_any_instance_of(benefits_intake_gateway).to receive(:lighthouse_submissions).and_return([])
      allow_any_instance_of(benefits_intake_gateway).to receive(:intake_statuses).and_return([nil, nil])
    end

    it 'returns an empty array' do
      result = subject.run
      expect(result.submission_statuses).to eq([])
    end
  end

  context 'when user has form submissions only' do
    before do
      create(:form_submission, :with_form214142, user_account_id: user_account.id)
      create(:form_submission, :with_form210845, user_account_id: user_account.id)
      create(:form_submission, :with_form214140, user_account_id: user_account.id)

      # This form is not in the allowed forms list and should not be included
      create(:form_submission, :with_form_blocked, user_account_id: user_account.id)

      # This 20-10207 form is older than 60 days and should not be included in the results
      create(:form_submission, :with_form2010207, user_account_id: user_account.id)

      allow_any_instance_of(benefits_intake_gateway).to receive(:lighthouse_submissions).and_return([])
    end

    context 'has statuses' do
      before do
        # Mock successful bulk_status response
        allow(BenefitsIntake::Service).to receive(:new).and_return(benefits_intake_service)
        allow(benefits_intake_service).to receive(:bulk_status).and_return(
          double(body: {
                   'data' => [
                     {
                       'id' => '4b846069-e496-4f83-8587-42b570f24483',
                       'attributes' => {
                         'detail' => 'detail',
                         'guid' => '4b846069-e496-4f83-8587-42b570f24483',
                         'message' => 'message',
                         'status' => 'received',
                         'updated_at' => 2.days.ago
                       }
                     },
                     {
                       'id' => 'd0c6cea6-9885-4e2f-8e0c-708d5933833a',
                       'attributes' => {
                         'detail' => 'detail',
                         'guid' => 'd0c6cea6-9885-4e2f-8e0c-708d5933833a',
                         'message' => 'message',
                         'status' => 'received',
                         'updated_at' => 3.days.ago
                       }
                     },
                     {
                       'id' => 'a1b2c3d4-e496-4f83-8587-42b570f24483',
                       'attributes' => {
                         'detail' => 'detail',
                         'guid' => 'a1b2c3d4-e496-4f83-8587-42b570f24483',
                         'message' => 'message',
                         'status' => 'received',
                         'updated_at' => 1.day.ago
                       }
                     }
                   ]
                 })
        )
      end

      context 'when :hca_status_card_enabled is enabled' do
        subject(:report) do
          described_class.new(
            user_account:,
            allowed_forms:,
            gateway_options: {
              benefits_intake_enabled: true,
              hca_status_card_enabled: true,
              user_email: 'test@example.com'
            }
          )
        end

        before do
          allow(HealthCareApplication).to receive(:enrollment_status).with(user_account.icn, true).and_return(
            {
              application_date: (DateTime.current - 15.days).to_s,
              effective_date: (DateTime.current - 1.day).to_s,
              enrollment_date: 0.days.ago.to_s,
              preferred_facility: '988 - DAYT20',
              parsed_status: :enrolled,
              priority_group: 'Group 3',
              can_submit_financial_info: true
            }
          )
        end

        it 'returns the correct count' do
          result = subject.run

          expect(result.submission_statuses.size).to be(4)
          expect(result.errors).to be_empty
        end

        it 'sorts results' do
          result = subject.run

          submission_statuses = result.submission_statuses
          expect(submission_statuses.first.updated_at).to be <= submission_statuses.last.updated_at
        end

        it 'returns the correct values' do
          result = subject.run

          submission_status = result.submission_statuses.first
          expect(submission_status.id).to eq('d0c6cea6-9885-4e2f-8e0c-708d5933833a')
          expect(submission_status.detail).to eq('detail')
          expect(submission_status.form_type).to eq('21-0845')
          expect(submission_status.message).to eq('message')
          expect(submission_status.status).to eq('received')
          expect(submission_status.pdf_support).to be(true)
        end
      end

      context 'when :hca_status_card_enabled is disabled' do
        it 'returns the correct count' do
          result = subject.run

          expect(result.submission_statuses.size).to be(3)
          expect(result.errors).to be_empty
        end

        it 'sorts results' do
          result = subject.run

          submission_statuses = result.submission_statuses
          expect(submission_statuses.first.updated_at).to be <= submission_statuses.last.updated_at
        end

        it 'returns the correct values' do
          result = subject.run

          submission_status = result.submission_statuses.first
          expect(submission_status.id).to eq('d0c6cea6-9885-4e2f-8e0c-708d5933833a')
          expect(submission_status.detail).to eq('detail')
          expect(submission_status.form_type).to eq('21-0845')
          expect(submission_status.message).to eq('message')
          expect(submission_status.status).to eq('received')
          expect(submission_status.pdf_support).to be(true)
        end
      end
    end
  end

  context 'when user has lighthouse submissions only' do
    let!(:saved_claim) { create(:burials_saved_claim, :pending, user_account:) }
    let!(:lighthouse_submission) { saved_claim.lighthouse_submissions.first }

    before do
      allow_any_instance_of(benefits_intake_gateway).to receive(:form_submissions).and_return([])
    end

    context 'has statuses' do
      before do
        benefits_intake_uuid = lighthouse_submission.submission_attempts.last&.benefits_intake_uuid || 'test-uuid-123'
        lighthouse_intake_statuses = [
          [
            {
              'id' => benefits_intake_uuid,
              'attributes' => {
                'detail' => 'lighthouse detail',
                'guid' => benefits_intake_uuid,
                'message' => 'lighthouse message',
                'status' => 'pending',
                'updated_at' => 1.day.ago
              }
            }
          ],
          nil
        ]

        allow_any_instance_of(benefits_intake_gateway).to receive(
          :intake_statuses
        ).and_return(lighthouse_intake_statuses)
      end

      it 'returns lighthouse submission data' do
        result = subject.run

        expect(result.submission_statuses.size).to be(1)
        submission_status = result.submission_statuses.first

        benefits_intake_uuid = lighthouse_submission.submission_attempts.last&.benefits_intake_uuid || 'test-uuid-123'
        expect(submission_status.id).to eq(benefits_intake_uuid)
        expect(submission_status.form_type).to eq('21P-530EZ')
        expect(submission_status.status).to eq('pending')
      end
    end
  end

  context 'when user has mixed submissions' do
    let!(:saved_claim) { create(:burials_saved_claim, :pending, user_account:) }
    let!(:lighthouse_submission) { saved_claim.lighthouse_submissions.first }

    before do
      create(:form_submission, :with_form214142, user_account_id: user_account.id)
    end

    context 'combines both submission types' do
      before do
        benefits_intake_uuid = lighthouse_submission.submission_attempts.last&.benefits_intake_uuid || 'test-uuid-123'
        mixed_intake_statuses = [
          [
            {
              'id' => '4b846069-e496-4f83-8587-42b570f24483',
              'attributes' => {
                'status' => 'received',
                'updated_at' => 2.days.ago,
                'detail' => 'form submission detail',
                'guid' => '4b846069-e496-4f83-8587-42b570f24483',
                'message' => 'form submission message'
              }
            },
            {
              'id' => benefits_intake_uuid,
              'attributes' => {
                'status' => 'processing',
                'updated_at' => 1.day.ago,
                'detail' => 'lighthouse detail',
                'guid' => benefits_intake_uuid,
                'message' => 'lighthouse message'
              }
            }
          ],
          nil
        ]

        allow_any_instance_of(benefits_intake_gateway).to receive(
          :intake_statuses
        ).and_return(mixed_intake_statuses)
      end

      it 'returns combined submission count' do
        result = subject.run

        expect(result.submission_statuses.size).to be(2)

        # Check we have both types
        form_types = result.submission_statuses.map(&:form_type)
        expect(form_types).to include('21-4142', '21P-530EZ')
      end

      it 'sorts by creation time across both types' do
        result = subject.run

        submission_statuses = result.submission_statuses
        expect(submission_statuses.first.updated_at).to be <= submission_statuses.last.updated_at

        # Verify the sorting order - older should come first
        expect(submission_statuses.first.updated_at.to_date).to eq(2.days.ago.to_date)
        expect(submission_statuses.last.updated_at.to_date).to eq(1.day.ago.to_date)
      end
    end
  end

  context 'when no statuses' do
    before do
      create(:form_submission, :with_form214142, user_account_id: user_account.id)

      allow_any_instance_of(benefits_intake_gateway).to receive(:lighthouse_submissions).and_return([])
      allow_any_instance_of(benefits_intake_gateway).to receive(:intake_statuses).and_return([nil, nil])
    end

    it 'returns the correct count' do
      result = subject.run

      expect(result.submission_statuses.size).to be(1)
    end

    it 'returns the correct values' do
      result = subject.run

      submission_status = result.submission_statuses.first
      expect(submission_status.id).to eq('4b846069-e496-4f83-8587-42b570f24483')
      expect(submission_status.detail).to be_nil
      expect(submission_status.form_type).to eq('21-4142')
      expect(submission_status.message).to be_nil
      expect(submission_status.status).to be_nil
      expect(submission_status.pdf_support).to be(true)
    end
  end

  context 'when ivc champva gateway is enabled' do
    subject(:report) do
      described_class.new(
        user_account:,
        allowed_forms:,
        gateway_options: {
          benefits_intake_enabled: false,
          decision_reviews_enabled: false,
          ivc_champva_enabled: true,
          hca_status_card_enabled: false,
          user_email: 'test@example.com'
        }
      )
    end

    before do
      create(
        :ivc_champva_form,
        email: 'test@example.com',
        form_number: '10-10D-EXTENDED',
        form_uuid: SecureRandom.uuid,
        s3_status: '[200]',
        pega_status: 'Processed',
        ves_status: nil
      )
      create(
        :ivc_champva_form,
        email: 'other@example.com',
        form_number: '10-10d',
        form_uuid: SecureRandom.uuid,
        s3_status: '[200]',
        pega_status: 'Processed',
        ves_status: nil
      )
    end

    it 'returns ivc champva submissions for the current user only' do
      result = report.run

      expect(result.submission_statuses.size).to eq(1)
      expect(result.submission_statuses.first.form_type).to eq('10-10D')
      expect(result.submission_statuses.first.status).to eq('vbms')
    end
  end

  context 'when user has a 21-4138 submission' do
    before do
      create(:form_submission, :with_form214138, user_account_id: user_account.id)

      allow_any_instance_of(benefits_intake_gateway).to receive(:lighthouse_submissions).and_return([])
      allow(BenefitsIntake::Service).to receive(:new).and_return(benefits_intake_service)
      allow(benefits_intake_service).to receive(:bulk_status).and_return(
        double(body: {
                 'data' => [
                   {
                     'id' => 'c7e1f2a3-b4d5-4e6f-9a0b-1c2d3e4f5a6b',
                     'attributes' => {
                       'detail' => 'detail',
                       'guid' => 'c7e1f2a3-b4d5-4e6f-9a0b-1c2d3e4f5a6b',
                       'message' => 'message',
                       'status' => 'received',
                       'updated_at' => 1.day.ago
                     }
                   }
                 ]
               })
      )
    end

    it 'includes the 21-4138 submission in the results' do
      result = subject.run

      form_types = result.submission_statuses.map(&:form_type)
      expect(form_types).to include('21-4138')
    end

    it 'returns the correct values for a 21-4138 submission' do
      result = subject.run

      submission_status = result.submission_statuses.find { |s| s.form_type == '21-4138' }
      expect(submission_status).not_to be_nil
      expect(submission_status.id).to eq('c7e1f2a3-b4d5-4e6f-9a0b-1c2d3e4f5a6b')
      expect(submission_status.status).to eq('received')
      expect(submission_status.pdf_support).to be(true)
    end
  end

  context 'logging errors' do
    let(:logger) { Rails.logger }

    context 'when gateway returns errors' do
      before do
        # Create submissions so the gateway has data to process
        create(:form_submission, :with_form214142, user_account_id: user_account.id)

        # Mock service error response
        error_response = double(status: 500, body: { 'errors' => [{ 'detail' => 'Service unavailable' }] })
        allow(BenefitsIntake::Service).to receive(:new).and_return(benefits_intake_service)
        allow(benefits_intake_service).to receive(:bulk_status).and_raise(
          Common::Exceptions::BackendServiceException.new('BENEFITS_INTAKE_ERROR', {},
                                                          error_response.status,
                                                          error_response.body)
        )
      end

      it 'logs gateway errors for benefits intake' do
        expect(logger).to receive(:error).with(
          'Gateway errors encountered when retrieving data in Forms::SubmissionStatuses::Report',
          hash_including(
            service: 'lighthouse_benefits_intake',
            errors: instance_of(Array)
          )
        )

        subject.run
      end
    end

    context 'when formatter is missing' do
      before do
        stub_const('Forms::SubmissionStatuses::Report::FORMATTERS', {})
      end

      it 'logs missing formatter error' do
        expect(logger).to receive(:error).with(
          'Report execution failed in Forms::SubmissionStatuses::Report',
          hash_including(
            error: 'Missing formatter for service: lighthouse_benefits_intake',
            service: 'lighthouse_benefits_intake',
            error_source: 'data_formatting'
          )
        )

        expect { subject.run }.to raise_error(RuntimeError)
      end
    end

    context 'when an unexpected error occurs' do
      context 'when retrieving data' do
        before do
          # Create submissions so the gateway has data to process
          create(:form_submission, :with_form214142, user_account_id: user_account.id)

          # Mock an error that will cause the gateway to fail at the gateway level
          # This simulates a scenario where the gateway itself fails, not just the service call
          allow_any_instance_of(benefits_intake_gateway).to receive(:data).and_raise(StandardError, 'Unexpected error')
        end

        it 'logs unexpected errors' do
          expect(logger).to receive(:error).with(
            'Report execution failed in Forms::SubmissionStatuses::Report',
            hash_including(
              error: 'Unexpected error',
              service: 'lighthouse_benefits_intake',
              error_source: 'data_retrieval_from_gateway'
            )
          )

          expect { subject.run }.to raise_error(StandardError)
        end
      end

      context 'when formatting data' do
        let(:formatter) { instance_double(Forms::SubmissionStatuses::Formatters::BenefitsIntakeFormatter) }

        before do
          allow_any_instance_of(benefits_intake_gateway)
            .to receive(:data)
            .and_return(OpenStruct.new(submissions?: true, errors: []))

          stub_const(
            'Forms::SubmissionStatuses::Report::FORMATTERS',
            { 'lighthouse_benefits_intake' => formatter }
          )

          allow(formatter)
            .to receive(:format_data)
            .and_raise(StandardError, 'Formatter error')
        end

        it 'logs formatter errors' do
          expect(logger).to receive(:error).with(
            'Report execution failed in Forms::SubmissionStatuses::Report',
            hash_including(
              error: 'Formatter error',
              service: 'lighthouse_benefits_intake',
              error_source: 'data_formatting'
            )
          )

          expect { subject.run }.to raise_error(StandardError)
        end
      end
    end
  end

  context 'StatsD metrics' do
    context 'when gateway succeeds' do
      before do
        allow_any_instance_of(benefits_intake_gateway).to receive(:submissions).and_return([])
        allow_any_instance_of(benefits_intake_gateway).to receive(:lighthouse_submissions).and_return([])
        allow_any_instance_of(benefits_intake_gateway).to receive(:intake_statuses).and_return([nil, nil])
      end

      it 'increments success metric for the gateway' do
        expect(StatsD).to receive(:increment).with(
          'api.forms.submission_statuses.gateway',
          tags: ['service:lighthouse_benefits_intake', 'result:success']
        )
        expect(StatsD).to receive(:measure).with(
          'api.forms.submission_statuses.gateway.latency',
          instance_of(Float),
          tags: ['service:lighthouse_benefits_intake']
        )

        subject.run
      end
    end

    context 'when gateway returns errors' do
      before do
        create(:form_submission, :with_form214142, user_account_id: user_account.id)

        error_response = double(status: 500, body: { 'errors' => [{ 'detail' => 'Service unavailable' }] })
        allow(BenefitsIntake::Service).to receive(:new).and_return(benefits_intake_service)
        allow(benefits_intake_service).to receive(:bulk_status).and_raise(
          Common::Exceptions::BackendServiceException.new('BENEFITS_INTAKE_ERROR', {},
                                                          error_response.status,
                                                          error_response.body)
        )
      end

      it 'increments error metric for the gateway' do
        allow(StatsD).to receive(:increment)
        expect(StatsD).to receive(:increment).with(
          'api.forms.submission_statuses.gateway',
          tags: ['service:lighthouse_benefits_intake', 'result:error']
        )
        allow(StatsD).to receive(:measure)
        allow(Rails.logger).to receive(:error)

        subject.run
      end
    end

    context 'when multiple gateways are enabled' do
      subject(:report) do
        described_class.new(
          user_account:,
          allowed_forms:,
          gateway_options: {
            benefits_intake_enabled: true,
            decision_reviews_enabled: true
          }
        )
      end

      before do
        allow_any_instance_of(benefits_intake_gateway).to receive(:submissions).and_return([])
        allow_any_instance_of(benefits_intake_gateway).to receive(:lighthouse_submissions).and_return([])
        allow_any_instance_of(benefits_intake_gateway).to receive(:intake_statuses).and_return([nil, nil])

        allow_any_instance_of(Forms::SubmissionStatuses::Gateways::DecisionReviewsGateway)
          .to receive(:submissions).and_return([])
      end

      it 'emits metrics for each gateway' do
        expect(StatsD).to receive(:increment).with(
          'api.forms.submission_statuses.gateway',
          tags: ['service:lighthouse_benefits_intake', 'result:success']
        )
        expect(StatsD).to receive(:increment).with(
          'api.forms.submission_statuses.gateway',
          tags: ['service:decision_reviews', 'result:success']
        )
        allow(StatsD).to receive(:measure)

        report.run
      end
    end

    context 'status distribution per gateway' do
      before do
        allow(StatsD).to receive(:increment)
        allow(StatsD).to receive(:measure)
      end

      context 'for a single gateway with multiple status values' do
        before do
          create(:form_submission, :with_form214142, user_account_id: user_account.id)
          create(:form_submission, :with_form214140, user_account_id: user_account.id)
          create(:form_submission, :with_form210845, user_account_id: user_account.id)

          allow_any_instance_of(benefits_intake_gateway).to receive(:lighthouse_submissions).and_return([])
          allow(BenefitsIntake::Service).to receive(:new).and_return(benefits_intake_service)
          allow(benefits_intake_service).to receive(:bulk_status).and_return(
            double(body: {
                     'data' => [
                       { 'id' => '4b846069-e496-4f83-8587-42b570f24483',
                         'attributes' => { 'guid' => '4b846069-e496-4f83-8587-42b570f24483',
                                           'status' => 'error', 'updated_at' => 1.day.ago } },
                       { 'id' => 'a1b2c3d4-e496-4f83-8587-42b570f24483',
                         'attributes' => { 'guid' => 'a1b2c3d4-e496-4f83-8587-42b570f24483',
                                           'status' => 'error', 'updated_at' => 1.day.ago } },
                       { 'id' => 'd0c6cea6-9885-4e2f-8e0c-708d5933833a',
                         'attributes' => { 'guid' => 'd0c6cea6-9885-4e2f-8e0c-708d5933833a',
                                           'status' => 'expired', 'updated_at' => 1.day.ago } }
                     ]
                   })
          )
        end

        it 'emits a per-status counter aggregated by status value' do
          expect(StatsD).to receive(:increment).with(
            'api.forms.submission_statuses.gateway.status', 2,
            tags: ['service:lighthouse_benefits_intake', 'status:error']
          )
          expect(StatsD).to receive(:increment).with(
            'api.forms.submission_statuses.gateway.status', 1,
            tags: ['service:lighthouse_benefits_intake', 'status:expired']
          )

          subject.run
        end

        it 'keeps error and expired distinguishable per gateway' do
          subject.run

          expect(StatsD).to have_received(:increment).with(
            'api.forms.submission_statuses.gateway.status', 2,
            tags: ['service:lighthouse_benefits_intake', 'status:error']
          )
          expect(StatsD).to have_received(:increment).with(
            'api.forms.submission_statuses.gateway.status', 1,
            tags: ['service:lighthouse_benefits_intake', 'status:expired']
          )
        end
      end

      context 'when the status is nil' do
        before do
          create(:form_submission, :with_form214142, user_account_id: user_account.id)

          allow_any_instance_of(benefits_intake_gateway).to receive(:lighthouse_submissions).and_return([])
          allow_any_instance_of(benefits_intake_gateway).to receive(:intake_statuses).and_return([nil, nil])
        end

        it 'reports the status as none' do
          expect(StatsD).to receive(:increment).with(
            'api.forms.submission_statuses.gateway.status', 1,
            tags: ['service:lighthouse_benefits_intake', 'status:none']
          )

          subject.run
        end
      end

      context 'when the status is not in the known allowlist' do
        before do
          create(:form_submission, :with_form214142, user_account_id: user_account.id)

          allow_any_instance_of(benefits_intake_gateway).to receive(:lighthouse_submissions).and_return([])
          allow(BenefitsIntake::Service).to receive(:new).and_return(benefits_intake_service)
          allow(benefits_intake_service).to receive(:bulk_status).and_return(
            double(body: {
                     'data' => [
                       { 'id' => '4b846069-e496-4f83-8587-42b570f24483',
                         'attributes' => { 'guid' => '4b846069-e496-4f83-8587-42b570f24483',
                                           'status' => 'some_unexpected_value', 'updated_at' => 1.day.ago } }
                     ]
                   })
          )
        end

        it 'buckets the status into other to bound cardinality' do
          expect(StatsD).to receive(:increment).with(
            'api.forms.submission_statuses.gateway.status', 1,
            tags: ['service:lighthouse_benefits_intake', 'status:other']
          )

          subject.run
        end

        it 'logs the raw unrecognized status value with its count and gateway' do
          expect(Rails.logger).to receive(:warn).with(
            'Unrecognized submission status(es) bucketed to "other" in Forms::SubmissionStatuses::Report',
            service: 'lighthouse_benefits_intake',
            unrecognized_statuses: { 'some_unexpected_value' => 1 }
          )

          subject.run
        end
      end

      context 'when all statuses are recognized' do
        before do
          create(:form_submission, :with_form214142, user_account_id: user_account.id)

          allow_any_instance_of(benefits_intake_gateway).to receive(:lighthouse_submissions).and_return([])
          allow(BenefitsIntake::Service).to receive(:new).and_return(benefits_intake_service)
          allow(benefits_intake_service).to receive(:bulk_status).and_return(
            double(body: {
                     'data' => [
                       { 'id' => '4b846069-e496-4f83-8587-42b570f24483',
                         'attributes' => { 'guid' => '4b846069-e496-4f83-8587-42b570f24483',
                                           'status' => 'received', 'updated_at' => 1.day.ago } }
                     ]
                   })
          )
        end

        it 'does not log any unrecognized status warning' do
          expect(Rails.logger).not_to receive(:warn).with(
            'Unrecognized submission status(es) bucketed to "other" in Forms::SubmissionStatuses::Report',
            anything
          )

          subject.run
        end
      end

      context "when the status is 'submitted' or 'submitting'" do
        before do
          create(:form_submission, :with_form214142, user_account_id: user_account.id)
          create(:form_submission, :with_form214140, user_account_id: user_account.id)

          allow_any_instance_of(benefits_intake_gateway).to receive(:lighthouse_submissions).and_return([])
          allow(BenefitsIntake::Service).to receive(:new).and_return(benefits_intake_service)
          allow(benefits_intake_service).to receive(:bulk_status).and_return(
            double(body: {
                     'data' => [
                       { 'id' => '4b846069-e496-4f83-8587-42b570f24483',
                         'attributes' => { 'guid' => '4b846069-e496-4f83-8587-42b570f24483',
                                           'status' => 'submitted', 'updated_at' => 1.day.ago } },
                       { 'id' => 'a1b2c3d4-e496-4f83-8587-42b570f24483',
                         'attributes' => { 'guid' => 'a1b2c3d4-e496-4f83-8587-42b570f24483',
                                           'status' => 'submitting', 'updated_at' => 1.day.ago } }
                     ]
                   })
          )
        end

        it 'tracks submitted as its own status rather than bucketing it into other' do
          expect(StatsD).to receive(:increment).with(
            'api.forms.submission_statuses.gateway.status', 1,
            tags: ['service:lighthouse_benefits_intake', 'status:submitted']
          )

          subject.run
        end

        it 'tracks submitting as its own status rather than bucketing it into other' do
          expect(StatsD).to receive(:increment).with(
            'api.forms.submission_statuses.gateway.status', 1,
            tags: ['service:lighthouse_benefits_intake', 'status:submitting']
          )

          subject.run
        end

        it 'does not log an unrecognized status warning for either status' do
          expect(Rails.logger).not_to receive(:warn).with(
            'Unrecognized submission status(es) bucketed to "other" in Forms::SubmissionStatuses::Report',
            anything
          )

          subject.run
        end
      end

      context 'across multiple gateways' do
        subject(:report) do
          described_class.new(
            user_account:,
            allowed_forms:,
            gateway_options: {
              benefits_intake_enabled: true,
              ivc_champva_enabled: true,
              user_email: 'test@example.com'
            }
          )
        end

        before do
          create(:form_submission, :with_form214142, user_account_id: user_account.id)
          allow_any_instance_of(benefits_intake_gateway).to receive(:lighthouse_submissions).and_return([])
          allow(BenefitsIntake::Service).to receive(:new).and_return(benefits_intake_service)
          allow(benefits_intake_service).to receive(:bulk_status).and_return(
            double(body: {
                     'data' => [
                       { 'id' => '4b846069-e496-4f83-8587-42b570f24483',
                         'attributes' => { 'guid' => '4b846069-e496-4f83-8587-42b570f24483',
                                           'status' => 'received', 'updated_at' => 1.day.ago } }
                     ]
                   })
          )

          create(
            :ivc_champva_form,
            email: 'test@example.com',
            form_number: '10-10D',
            form_uuid: SecureRandom.uuid,
            s3_status: '[200]',
            pega_status: 'Processed',
            ves_status: nil
          )
        end

        it 'tags each status counter with its originating gateway' do
          expect(StatsD).to receive(:increment).with(
            'api.forms.submission_statuses.gateway.status', 1,
            tags: ['service:lighthouse_benefits_intake', 'status:received']
          )
          expect(StatsD).to receive(:increment).with(
            'api.forms.submission_statuses.gateway.status', 1,
            tags: ['service:ivc_champva', 'status:vbms']
          )

          report.run
        end
      end

      context 'when a gateway produces a symbol status' do
        subject(:report) do
          described_class.new(
            user_account:,
            allowed_forms:,
            gateway_options: {
              benefits_intake_enabled: true,
              hca_status_card_enabled: true,
              user_email: 'test@example.com'
            }
          )
        end

        before do
          allow_any_instance_of(benefits_intake_gateway).to receive(:submissions).and_return([])
          allow_any_instance_of(benefits_intake_gateway).to receive(:lighthouse_submissions).and_return([])
          allow_any_instance_of(benefits_intake_gateway).to receive(:intake_statuses).and_return([nil, nil])

          # HCA1010EZ maps parsed_status :enrolled to the symbol :vbms
          allow(HealthCareApplication).to receive(:enrollment_status).with(user_account.icn, true).and_return(
            {
              application_date: (DateTime.current - 15.days).to_s,
              effective_date: (DateTime.current - 1.day).to_s,
              parsed_status: :enrolled
            }
          )
        end

        it 'coerces the symbol status to a string and matches the known allowlist' do
          expect(StatsD).to receive(:increment).with(
            'api.forms.submission_statuses.gateway.status', 1,
            tags: ['service:hca1010_ez', 'status:vbms']
          )

          report.run
        end

        it 'does not bucket the recognized symbol status into other' do
          expect(StatsD).not_to receive(:increment).with(
            'api.forms.submission_statuses.gateway.status', anything,
            tags: ['service:hca1010_ez', 'status:other']
          )

          report.run
        end

        it 'does not log an unrecognized status warning for a recognized symbol status' do
          expect(Rails.logger).not_to receive(:warn).with(
            'Unrecognized submission status(es) bucketed to "other" in Forms::SubmissionStatuses::Report',
            anything
          )

          report.run
        end
      end
    end
  end
end
