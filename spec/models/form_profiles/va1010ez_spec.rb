# frozen_string_literal: true

require 'rails_helper'

RSpec.describe FormProfiles::VA1010ez do
  subject(:profile) { described_class.new(form_id: '1010ez', user:) }

  let(:user) { create(:user, icn: '123498767V234859') }

  describe '#metadata' do
    it 'returns expected metadata' do
      expect(profile.metadata).to eq({ version: 0, prefill: true, returnUrl: '/check-your-personal-information' })
    end
  end
end
