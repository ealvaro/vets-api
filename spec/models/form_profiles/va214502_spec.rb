# frozen_string_literal: true

require 'rails_helper'

RSpec.describe FormProfiles::VA214502 do
  subject(:profile) { described_class.new(form_id: '21-4502', user:) }

  let(:user) { create(:user, :loa3) }

  describe '#metadata' do
    it 'returns expected metadata when flipper enabled' do
      allow(Flipper).to receive(:enabled?).with(:form214502_prefill_enabled).and_return(true)
      expect(profile.metadata).to eq(
        {
          version: 0,
          prefill: true,
          returnUrl: '/eligibility'
        }
      )
    end

    it 'returns expected metadata when flipper disabled' do
      allow(Flipper).to receive(:enabled?).with(:form214502_prefill_enabled).and_return(false)
      expect(profile.metadata).to eq(
        {
          version: 0,
          prefill: false,
          returnUrl: '/eligibility'
        }
      )
    end
  end

  describe '#prefill' do
    it 'prefills the veteran SSN from identity information flipper enabled' do
      allow(Flipper).to receive(:enabled?).with(:form214502_prefill_enabled).and_return(true)
      data = profile.prefill
      expect(data[:form_data]['veteran']['ssn']).to eq(user.ssn_normalized)
    end

    it 'prefills the veteran SSN from identity information flipper disabled' do
      allow(Flipper).to receive(:enabled?).with(:form214502_prefill_enabled).and_return(false)
      data = profile.prefill
      expect(data[:form_data]).to eq({})
    end
  end
end
