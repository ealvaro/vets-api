# frozen_string_literal: true

require 'rails_helper'

RSpec.describe SurvivorsBenefits::FormProfiles::VA21p534ez do
  subject(:profile) { described_class.new(form_id: '21P-534EZ', user:) }

  let(:user) { create(:user, icn: '123498767V234859') }

  describe '#metadata' do
    it 'returns expected metadata' do
      expect(profile.metadata).to eq({ version: 0, prefill: true, returnUrl: '/claimant-relationship' })
    end
  end
end
