# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Claims API v3 disability compensation routing', type: :routing do
  describe 'submit' do
    let(:controller) { 'claims_api/v3/veterans/disability_compensation' }

    it 'routes POST to disability_compensation#submit' do
      expect(post('/services/claims/v3/veterans/526')).to route_to(
        format: 'json',
        controller:,
        action: 'submit'
      )
    end
  end
end
