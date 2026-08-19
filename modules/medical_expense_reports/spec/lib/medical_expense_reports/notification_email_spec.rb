# frozen_string_literal: true

require 'rails_helper'
require 'medical_expense_reports/notification_email'

RSpec.describe MedicalExpenseReports::NotificationEmail, skip: 'TODO after schema built' do
  let(:saved_claim) { create(:medical_expense_reports_claim) }

  describe '#deliver' do
    it 'successfully sends an email' do
      expect(MedicalExpenseReports::SavedClaim).to receive(:find).with(23).and_return saved_claim
      expect(Settings.vanotify.services).to receive(:medical_expense_reports).and_call_original

      args = [
        saved_claim.email,
        Settings.vanotify.services['21p_8416'].email.submitted.template_id,
        anything,
        Settings.vanotify.services['21p_8416'].api_key,
        { callback_klass: MedicalExpenseReports::NotificationCallback.to_s,
          callback_metadata: anything }
      ]
      expect(VANotify::EmailJob).to receive(:perform_async).with(*args)

      described_class.new(23).deliver(:submitted)
    end
  end

  describe '#first_name' do
    subject { described_class.new(saved_claim.id) }

    before do
      subject.instance_variable_set(:@claim, saved_claim)
    end

    it 'titlecases an all-caps first name without splitting on inflection acronyms' do
      allow(saved_claim).to receive_messages(claimant_first_name: 'VANESSA', veteran_first_name: nil)
      expect(subject.send(:first_name)).to eq('Vanessa')
    end

    it 'preserves hyphenated all-caps names' do
      allow(saved_claim).to receive_messages(claimant_first_name: 'ANNE-MARIE', veteran_first_name: nil)
      expect(subject.send(:first_name)).to eq('Anne-Marie')
    end

    it 'defaults to Veteran when no name is available' do
      allow(saved_claim).to receive_messages(claimant_first_name: nil, veteran_first_name: nil)
      expect(subject.send(:first_name)).to eq('Veteran')
    end
  end
end
