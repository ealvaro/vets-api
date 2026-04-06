# frozen_string_literal: true

require 'rails_helper'

RSpec.describe FormProfiles::VA214140 do
  subject(:profile) { described_class.new(form_id: '21-4140', user:) }

  let(:user) { create(:user, :loa3) }

  describe '#metadata' do
    it 'returns expected metadata when flipper enabled' do
      allow(Flipper).to receive(:enabled?).with(:form214140_prefill_enabled).and_return(true)
      expect(profile.metadata).to eq(
        {
          version: 0,
          prefill: true,
          returnUrl: '/name-and-date-of-birth'
        }
      )
    end

    it 'returns expected metadata when flipper disabled' do
      allow(Flipper).to receive(:enabled?).with(:form214140_prefill_enabled).and_return(false)
      expect(profile.metadata).to eq(
        {
          version: 0,
          prefill: false,
          returnUrl: '/name-and-date-of-birth'
        }
      )
    end
  end

  describe '#prefill' do
    it 'prefills the veteran SSN from identity information flipper enabled' do
      allow(Flipper).to receive(:enabled?).with(:form214140_prefill_enabled).and_return(true)
      data = profile.prefill
      expect(data[:form_data]['idNumber']['ssn']).to eq(user.ssn_normalized)
    end

    it 'prefills the veteran SSN from identity information flipper disabled' do
      allow(Flipper).to receive(:enabled?).with(:form214140_prefill_enabled).and_return(false)
      data = profile.prefill
      expect(data[:form_data]).to eq({})
    end
  end
end
