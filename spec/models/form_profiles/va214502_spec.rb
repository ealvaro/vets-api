# frozen_string_literal: true

require 'rails_helper'

RSpec.describe FormProfiles::VA214502 do
  subject(:profile) { described_class.new(form_id: '21-4502', user:) }

  let(:user) { create(:user, :loa3) }

  describe '#metadata' do
    it 'returns expected metadata' do
      expect(profile.metadata).to eq(
        {
          version: 0,
          prefill: false,
          returnUrl: '/eligibility'
        }
      )
    end
  end
end
