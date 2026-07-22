# frozen_string_literal: true

require 'rails_helper'

RSpec.describe FormProfiles::VHA107959f2 do
  subject(:profile) { described_class.new(form_id: '10-7959F-2', user:) }

  let(:user) { create(:user, :loa3) }

  describe '#metadata' do
    it 'returns prefill true when flipper enabled' do
      allow(Flipper).to receive(:enabled?).with(:form_107959f2_prefill_enabled, user).and_return(true)
      expect(profile.metadata).to eq(
        {
          version: 0,
          prefill: true,
          returnUrl: '/personal-information'
        }
      )
    end

    it 'returns prefill false when flipper disabled' do
      allow(Flipper).to receive(:enabled?).with(:form_107959f2_prefill_enabled, user).and_return(false)
      expect(profile.metadata).to eq(
        {
          version: 0,
          prefill: false,
          returnUrl: '/personal-information'
        }
      )
    end
  end

  describe '#prefill' do
    context 'when flipper enabled' do
      before do
        allow(Flipper).to receive(:enabled?).with(:form_107959f2_prefill_enabled, user).and_return(true)
      end

      it 'returns populated form_data with veteran name' do
        data = profile.prefill
        full_name = data[:form_data]['veteran']['fullName']
        expect(full_name['first']).to eq(user.first_name&.capitalize)
        expect(full_name['last']).to eq(user.last_name&.capitalize)
      end

      it 'returns populated form_data with veteran SSN' do
        data = profile.prefill
        expect(data[:form_data]['veteran']['ssn']).to eq(user.ssn_normalized)
      end

      it 'returns metadata with prefill true' do
        data = profile.prefill
        expect(data[:metadata][:prefill]).to be true
      end
    end

    context 'when flipper disabled' do
      before do
        allow(Flipper).to receive(:enabled?).with(:form_107959f2_prefill_enabled, user).and_return(false)
      end

      it 'returns empty form_data' do
        data = profile.prefill
        expect(data[:form_data]).to eq({})
      end

      it 'returns metadata with prefill false' do
        data = profile.prefill
        expect(data[:metadata][:prefill]).to be false
      end
    end
  end
end
