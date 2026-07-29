# frozen_string_literal: true

require 'rails_helper'

RSpec.describe FormSubmission, feature: :form_submission, type: :model do
  let(:user_account) { create(:user_account) }

  describe 'associations' do
    it { is_expected.to belong_to(:saved_claim).optional }
    it { is_expected.to belong_to(:user_account).optional }
    it { is_expected.to have_many(:form_intake_submissions).dependent(:destroy) }
  end

  describe 'validations' do
    it { is_expected.to validate_presence_of(:form_type) }
  end

  describe '.with_latest_benefits_intake_uuid' do
    it 'scopes form_submission_attempts with a LATERAL join per form_submission.id' do
      sql = described_class.with_latest_benefits_intake_uuid(user_account).to_sql

      expect(sql).to include('LEFT JOIN LATERAL')
      expect(sql).to include('form_submission_id = form_submissions.id')
      expect(sql).to include('ORDER BY created_at DESC, id DESC')
      expect(sql).not_to include('DISTINCT ON')
    end

    it 'does not return submissions belonging to other user accounts' do
      create(:form_submission, user_account:, form_type: 'FORM-A')
      other_user = create(:user_account)
      other_submission = create(:form_submission, user_account: other_user, form_type: 'FORM-Z')
      create(:form_submission_attempt, form_submission: other_submission, benefits_intake_uuid: SecureRandom.uuid)

      results = described_class.with_latest_benefits_intake_uuid(user_account).to_a

      expect(results.map(&:id)).not_to include(other_submission.id)
      expect(results.map(&:form_type)).to eq(['FORM-A'])
    end

    it 'breaks created_at ties by choosing the attempt with the greater id' do
      form_submission = create(:form_submission, user_account:, form_type: 'FORM-A')
      shared_time = Time.current
      older_id_attempt = create(
        :form_submission_attempt,
        form_submission:,
        benefits_intake_uuid: SecureRandom.uuid,
        created_at: shared_time
      )
      newer_id_attempt = create(
        :form_submission_attempt,
        form_submission:,
        benefits_intake_uuid: SecureRandom.uuid,
        created_at: shared_time
      )

      result = described_class.with_latest_benefits_intake_uuid(user_account).first

      expect(newer_id_attempt.id).to be > older_id_attempt.id
      expect(result.benefits_intake_uuid).to eq(newer_id_attempt.benefits_intake_uuid)
    end
  end

  describe 'user form submission statuses' do
    before do
      @fsa, @fsb, @fsc = create_list(:form_submission, 3, user_account:)
                         .zip(%w[FORM-A FORM-B FORM-C])
                         .map do |submission, form_type|
        submission.update(form_type:)
        submission
      end

      @fsa1, @fsa2, @fsa3 = create_list(:form_submission_attempt, 3, form_submission: @fsa) do |attempt, index|
        attempt.update(benefits_intake_uuid: SecureRandom.uuid, created_at: (3 - index).days.ago)
      end

      @fsb1 = create(
        :form_submission_attempt,
        form_submission: @fsb,
        benefits_intake_uuid:
        SecureRandom.uuid,
        created_at: 1.day.ago
      )
    end

    context 'when form submission has no attempts' do
      it 'returns nil' do
        result = FormSubmission.with_latest_benefits_intake_uuid(user_account).with_form_types(['FORM-C']).first

        expect(result.benefits_intake_uuid).to be_nil
      end
    end

    context 'when form submission has multple attempts' do
      it 'returns the benefits_intake_id from the latest form submission attempt' do
        result = FormSubmission.with_latest_benefits_intake_uuid(user_account).with_form_types(['FORM-A']).first

        expect(result.benefits_intake_uuid).to eq(@fsa3.benefits_intake_uuid)
      end
    end

    context 'when form submission has a single attempt with uuid' do
      it 'returns the benefits_intake_id from the only form submission attempt' do
        result = FormSubmission.with_latest_benefits_intake_uuid(user_account).with_form_types(['FORM-B']).first

        expect(result.benefits_intake_uuid).to eq(@fsb1.benefits_intake_uuid)
      end
    end

    context 'when form submission has a single attempt with no uuid' do
      it 'returns nil' do
        @fsb1.update!(benefits_intake_uuid: nil)
        result = FormSubmission.with_latest_benefits_intake_uuid(user_account).with_form_types(['FORM-B']).first

        expect(result.benefits_intake_uuid).to be_nil
      end
    end

    context 'when a list of forms is provided' do
      it 'returns only the records that match the given forms' do
        form_types = %w[FORM-A FORM-B]
        results = FormSubmission.with_latest_benefits_intake_uuid(user_account).with_form_types(form_types).to_a

        expect(results.count).to eq(2)
        results.each { |form| expect(form_types).to include(form.form_type) }
      end
    end

    context 'when a list of forms is not provided' do
      it 'returns all records' do
        results = FormSubmission.with_form_types(nil).to_a

        expect(results.count).to eq(3)
      end
    end

    context 'latest_pending_attempt' do
      it 'returns db record' do
        form_submission = FormSubmission.with_form_types(nil).first

        expect(form_submission.latest_pending_attempt).not_to be_nil
      end
    end

    context 'non_failure_attempt' do
      it 'returns db record' do
        form_submission = FormSubmission.with_form_types(nil).first

        expect(form_submission.non_failure_attempt).not_to be_nil
      end
    end
  end

  describe '#latest_attempt' do
    it 'returns the newest, associated form_submission_attempt' do
      form_submission = create(:form_submission, created_at: 1.day.ago)
      create_list(:form_submission_attempt, 2, form_submission:, created_at: 1.day.ago)
      form_submission_attempt = create(:form_submission_attempt, form_submission:)

      expect(form_submission.latest_attempt).to eq form_submission_attempt
    end
  end
end
