# frozen_string_literal: true

require 'rails_helper'
require 'benefits_claims/providers/lighthouse/claim_serializer'
require 'benefits_claims/responses/claim_response'

RSpec.describe BenefitsClaims::Providers::Lighthouse::ClaimSerializer do
  describe '.add_repeat_ineligibility_alert' do
    it 'does not set repeatIneligibilityAlert when the DTO alert is blank' do
      dto = BenefitsClaims::Responses::ClaimResponse.new(id: '1', repeat_ineligibility_alert: nil)
      attributes = {}

      described_class.add_repeat_ineligibility_alert(attributes, dto)

      expect(attributes).not_to have_key('repeatIneligibilityAlert')
    end

    it 'sets repeatIneligibilityAlert to the DTO alert when present' do
      alert = { 'title' => 'title', 'description' => 'description' }
      dto = BenefitsClaims::Responses::ClaimResponse.new(id: '1', repeat_ineligibility_alert: alert)
      attributes = {}

      described_class.add_repeat_ineligibility_alert(attributes, dto)

      expect(attributes['repeatIneligibilityAlert']).to eq(alert)
    end
  end
end
