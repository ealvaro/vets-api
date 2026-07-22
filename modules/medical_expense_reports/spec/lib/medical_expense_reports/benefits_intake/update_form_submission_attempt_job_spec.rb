# frozen_string_literal: true

require 'rails_helper'
require 'medical_expense_reports/benefits_intake/update_form_submission_attempt_job'

RSpec.describe MedicalExpenseReports::BenefitsIntake::UpdateFormSubmissionAttemptJob do
  let(:job) { described_class.new }
  let(:user_account) { create(:user_account) }
  let(:claim) { create(:medical_expense_reports_claim, user_account:) }

  # Backfills use the Lighthouse polling records (created before every upload) as the
  # authoritative uuid source, so a delayed run can never write a stale uuid.
  def create_lighthouse_attempt(uuid, created_at: Time.zone.now)
    submission = create(:lighthouse_submission, saved_claim: claim, form_id: claim.form_id)
    create(:lighthouse_submission_attempt, submission:, benefits_intake_uuid: uuid, created_at:)
  end

  describe '#perform' do
    it 'backfills the FormSubmission and attempt using the latest Lighthouse intake uuid' do
      create_lighthouse_attempt('11111111-1111-4111-8111-111111111111', created_at: 1.day.ago)
      create_lighthouse_attempt('22222222-2222-4222-8222-222222222222')

      expect { job.perform(claim.id) }
        .to change(FormSubmission, :count).by(1)
        .and change(FormSubmissionAttempt, :count).by(1)

      submission = claim.form_submissions.last
      expect(submission.form_type).to eq(claim.form_id)
      expect(submission.user_account_id).to eq(user_account.id)
      expect(submission.latest_attempt.benefits_intake_uuid).to eq('22222222-2222-4222-8222-222222222222')
    end

    it 'refreshes an existing attempt instead of creating a duplicate' do
      described_class.update_form_submission_attempt(claim, '11111111-1111-4111-8111-111111111111')
      create_lighthouse_attempt('22222222-2222-4222-8222-222222222222')

      expect { job.perform(claim.id) }
        .to not_change(FormSubmission, :count)
        .and not_change(FormSubmissionAttempt, :count)

      expect(claim.form_submissions.last.latest_attempt.benefits_intake_uuid)
        .to eq('22222222-2222-4222-8222-222222222222')
    end

    it 'logs and writes nothing when the claim has no Lighthouse intake uuid' do
      claim # create before the logger expectation; factory creation logs unrelated errors
      allow(Rails.logger).to receive(:error)
      expect(Rails.logger).to receive(:error)
        .with(a_string_including('found no'), hash_including(:claim_id))

      expect { job.perform(claim.id) }
        .to not_change(FormSubmission, :count)
        .and not_change(FormSubmissionAttempt, :count)
    end

    # Unlike the submit job, a raise here is safe (no upload to duplicate) and is exactly
    # what triggers the Sidekiq retries that make the bookkeeping eventually consistent.
    it 'raises when the write fails so Sidekiq retries the backfill' do
      create_lighthouse_attempt('11111111-1111-4111-8111-111111111111')
      allow(FormSubmission).to receive(:create_with).and_raise(ActiveRecord::StatementInvalid.new('KMS unavailable'))

      expect { job.perform(claim.id) }.to raise_error(ActiveRecord::StatementInvalid)
    end
  end
end
