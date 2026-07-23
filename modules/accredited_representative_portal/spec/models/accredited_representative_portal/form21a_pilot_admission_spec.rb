# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AccreditedRepresentativePortal::Form21aPilotAdmission, type: :model do
  describe 'associations' do
    it 'belongs to a user_account' do
      admission = create(:form21a_pilot_admission)
      expect(admission.user_account).to be_a(UserAccount)
    end
  end

  describe 'status enum' do
    it 'defaults to started' do
      expect(described_class.new.status).to eq('started')
    end

    it 'exposes started and submitted values' do
      expect(described_class.statuses).to eq('started' => 'started', 'submitted' => 'submitted')
    end
  end

  describe 'one admission per user' do
    it 'raises on a second admission for the same user_account' do
      admission = create(:form21a_pilot_admission)

      expect do
        described_class.create!(user_account: admission.user_account)
      end.to raise_error(ActiveRecord::RecordNotUnique)
    end
  end

  describe 'submitted_at check constraint' do
    it 'rejects a submitted admission without a submitted_at' do
      expect do
        create(:form21a_pilot_admission, status: :submitted, submitted_at: nil)
      end.to raise_error(
        ActiveRecord::StatementInvalid,
        /check_ar_form21a_pilot_admissions_submitted_at_present/
      )
    end

    it 'allows a submitted admission that carries a submitted_at' do
      expect { create(:form21a_pilot_admission, :submitted) }.not_to raise_error
    end
  end
end
