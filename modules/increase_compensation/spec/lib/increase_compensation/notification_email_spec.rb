# frozen_string_literal: true

require 'rails_helper'
require 'increase_compensation/notification_email'

RSpec.describe IncreaseCompensation::NotificationEmail do
  let(:saved_claim) { create(:increase_compensation_claim) }

  # describe '#deliver' do
  #   it 'successfully sends an email' do
  #     expect(IncreaseCompensation::SavedClaim).to receive(:find).with(23).and_return saved_claim
  #     expect(Settings.vanotify.services).to receive(:increase_compensation).and_call_original

  #     args = [
  #       saved_claim.email,
  #       Settings.vanotify.services['21_8940v1'].email.submitted.template_id,
  #       anything,
  #       Settings.vanotify.services['21_8940v1'].api_key,
  #       { callback_klass: IncreaseCompensation::NotificationCallback.to_s,
  #         callback_metadata: anything }
  #     ]
  #     expect(VANotify::EmailJob).to receive(:perform_async).with(*args)

  #     described_class.new(23).deliver(:submitted)
  #   end
  # end

  describe '#claim_class' do
    it 'returns a SavedClaim class' do
      # expect(IncreaseCompensation::SavedClaim).to receive(:find).with(23).and_return saved_claim
      notifier = described_class.new(23)
      expect(notifier.send(:claim_class)).to be(IncreaseCompensation::SavedClaim)
    end
  end

  describe '#first_name' do
    subject { described_class.new(saved_claim.id) }

    before do
      subject.instance_variable_set(:@claim, saved_claim)
    end

    it 'titlecases an all-caps first name without splitting on inflection acronyms' do
      allow(saved_claim).to receive(:veteran_first_name).and_return('VANESSA')
      expect(subject.send(:first_name)).to eq('Vanessa')
    end

    it 'preserves hyphenated all-caps names' do
      allow(saved_claim).to receive(:veteran_first_name).and_return('ANNE-MARIE')
      expect(subject.send(:first_name)).to eq('Anne-Marie')
    end

    it 'falls back to the claimant first name' do
      allow(saved_claim).to receive_messages(veteran_first_name: nil, claimant_first_name: 'VANESSA')
      expect(subject.send(:first_name)).to eq('Vanessa')
    end

    it 'defaults to Veteran when no name is available' do
      allow(saved_claim).to receive(:veteran_first_name).and_return(nil)
      expect(subject.send(:first_name)).to eq('Veteran')
    end
  end
end
