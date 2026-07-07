# frozen_string_literal: true

require 'rails_helper'
require 'digital_forms_api/submission_helper'

RSpec.describe DigitalFormsApi::SubmissionHelper do
  let(:user_account) { create(:user_account) }
  let(:claim) { double('SavedClaim', guid: SecureRandom.uuid, claim_form_type: '21-686c', id: 123) }
  let(:payload) { { 'veteranInformation' => { 'ssnLastFour' => '1234' } } }
  let(:bip_submission) do
    {
      'submissionId' => SecureRandom.uuid,
      'claim' => { 'claimId' => '987654321', 'claimLabel' => '130DPEBNAJRE' },
      'document' => { 'documentId' => SecureRandom.uuid, 'seriesId' => SecureRandom.uuid }
    }
  end
  let(:success_response) { double('Faraday::Response', success?: true, body: { 'submission' => bip_submission }) }
  let(:service) { instance_double(DigitalFormsApi::Service::Submissions) }
  let(:record_failure_metric) { 'api.digital_forms_api.submission_helper.record_failure' }

  before { allow(DigitalFormsApi::Service::Submissions).to receive(:new).and_return(service) }

  def call_submit
    described_class.submit(claim:, payload:, participant_id: 'PID-1', claim_label: '130DPEBNAJRE', user_account:)
  end

  describe 'happy path' do
    before { allow(service).to receive(:submit).and_return(success_response) }

    it 'sends the faithful BIP metadata envelope and returns the submission hash', :aggregate_failures do
      expect(service).to receive(:submit).with(
        payload,
        { sourceRequestId: claim.guid, formId: '21-686c', veteranId: 'PID-1',
          claimantId: 'PID-1', epCode: '130', claimLabel: '130DPEBNAJRE' }
      ).and_return(success_response)
      expect(call_submit).to eq(bip_submission)
    end

    it 'creates one Submission + one pending SubmissionAttempt, populated and cascaded', :aggregate_failures do
      expect { call_submit }
        .to change(DigitalFormsApi::Submission, :count).by(1)
        .and change(DigitalFormsApi::SubmissionAttempt, :count).by(1)

      sub = DigitalFormsApi::Submission.last
      expect(sub).to have_attributes(
        form_id: '21-686c', user_account_id: user_account.id, saved_claim_id: 123,
        claim_guid: claim.guid, bip_submission_id: bip_submission['submissionId'], latest_status: 'pending'
      )
      expect(sub.reload.reference_data).to include(
        'ep_code' => '130', 'claim_label' => '130DPEBNAJRE', 'source_request_id' => claim.guid
      )

      att = sub.submission_attempts.last
      expect(att.status).to eq('pending')
      expect(att.reload.metadata).to include('formId' => '21-686c', 'epCode' => '130')
      expect(att.response).to eq('submission' => bip_submission)
    end
  end

  describe 'non-success upstream response' do
    let(:failure_response) { double('Faraday::Response', success?: false, to_s: '500 upstream error') }

    before { allow(service).to receive(:submit).and_return(failure_response) }

    it 'raises and persists nothing', :aggregate_failures do
      expect { call_submit }.to raise_error(RuntimeError, '500 upstream error')
      expect(DigitalFormsApi::Submission.count).to eq(0)
      expect(DigitalFormsApi::SubmissionAttempt.count).to eq(0)
    end
  end

  describe 'persistence is best-effort (failures logged + tracked, never bubbled)' do
    before do
      allow(service).to receive(:submit).and_return(success_response)
      allow(Rails.logger).to receive(:error)
      allow(StatsD).to receive(:increment)
    end

    it 'rolls back both rows when the Submission insert fails, then swallows', :aggregate_failures do
      allow(DigitalFormsApi::Submission).to receive(:create!)
        .and_raise(ActiveRecord::RecordInvalid.new(DigitalFormsApi::Submission.new))

      result = nil
      expect { result = call_submit }
        .to not_change(DigitalFormsApi::Submission, :count)
        .and not_change(DigitalFormsApi::SubmissionAttempt, :count)
      expect(result).to eq(bip_submission)
      expect(Rails.logger).to have_received(:error).with(
        'DigitalFormsApi::SubmissionHelper failed to record Submission/SubmissionAttempt',
        hash_including(bip_submission_id: bip_submission['submissionId'], form_id: '21-686c')
      )
      expect(StatsD).to have_received(:increment).with(record_failure_metric, tags: ['form_id:21-686c'])
    end

    it 'rolls back the parent Submission when the attempt insert fails (no orphan)', :aggregate_failures do
      failing = double('submission_attempts')
      allow(failing).to receive(:create!)
        .and_raise(ActiveRecord::RecordInvalid.new(DigitalFormsApi::SubmissionAttempt.new))
      allow_any_instance_of(DigitalFormsApi::Submission).to receive(:submission_attempts).and_return(failing)

      result = nil
      expect { result = call_submit }.to not_change(DigitalFormsApi::Submission, :count)
      expect(result).to eq(bip_submission)
      expect(StatsD).to have_received(:increment).with(record_failure_metric, tags: ['form_id:21-686c'])
    end
  end

  describe 'idempotency — a repeat submit with the same submissionId does not duplicate' do
    before { allow(service).to receive(:submit).and_return(success_response) }

    it 'keeps exactly one Submission and flags the duplicate as a record_failure', :aggregate_failures do
      call_submit
      allow(Rails.logger).to receive(:error)
      allow(StatsD).to receive(:increment)

      result = nil
      expect { result = call_submit }
        .to not_change(DigitalFormsApi::Submission, :count)
        .and not_change(DigitalFormsApi::SubmissionAttempt, :count)
      expect(result).to eq(bip_submission)
      expect(DigitalFormsApi::Submission.where(bip_submission_id: bip_submission['submissionId']).count).to eq(1)
      expect(StatsD).to have_received(:increment).with(record_failure_metric, tags: ['form_id:21-686c'])
    end
  end

  describe 'upstream success without a submissionId (nothing durable to key on)' do
    let(:bip_submission) { { 'claim' => { 'claimId' => '987654321' } } }

    before do
      allow(service).to receive(:submit).and_return(success_response)
      allow(Rails.logger).to receive(:warn)
    end

    it 'persists nothing, warns, and still returns the hash', :aggregate_failures do
      result = nil
      expect { result = call_submit }
        .to not_change(DigitalFormsApi::Submission, :count)
        .and not_change(DigitalFormsApi::SubmissionAttempt, :count)
      expect(result).to eq(bip_submission)
      expect(Rails.logger).to have_received(:warn).with(
        'DigitalFormsApi::SubmissionHelper skipped persistence: upstream success without a submissionId',
        hash_including(form_id: '21-686c')
      )
    end
  end
end
