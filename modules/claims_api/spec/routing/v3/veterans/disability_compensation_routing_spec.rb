# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Claims API v3 disability compensation routing', type: :routing do
  describe 'submit' do
    let(:icn) { '1012861229V078999' } # Janet Moore
    let(:controller) { 'claims_api/v3/veterans/disability_compensation' }

    it 'routes POST /veterans/:veteranId/526 to disability_compensation#submit' do
      expect(post("/services/claims/v3/veterans/#{icn}/526")).to route_to(
        format: 'json',
        controller:,
        action: 'submit',
        veteranId: icn
      )
    end
  end
end
