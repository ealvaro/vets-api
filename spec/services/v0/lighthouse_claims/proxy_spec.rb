# frozen_string_literal: true

require 'rails_helper'

RSpec.describe V0::LighthouseClaims::Proxy do
  let(:user) { double('User') }
  let(:proxy) { described_class.new(user) }
  let(:provider) { double('LighthouseBenefitsClaimsProvider') }
  let(:claim_id) { '123' }

  before do
    allow(BenefitsClaims::Providers::Lighthouse::LighthouseBenefitsClaimsProvider)
      .to receive(:new).with(user).and_return(provider)
  end

  describe '#get_claims' do
    it 'delegates to the lighthouse provider' do
      claims_response = { 'data' => [{ 'id' => '1' }, { 'id' => '2' }] }
      allow(provider).to receive(:get_claims).and_return(claims_response)

      result = proxy.get_claims

      expect(result).to eq(claims_response)
      expect(provider).to have_received(:get_claims)
    end
  end

  describe '#get_claim' do
    let(:base_claim) do
      {
        'data' => {
          'id' => claim_id,
          'attributes' => {
            'trackedItems' => []
          }
        }
      }
    end

    it 'delegates to the lighthouse provider and applies transforms' do
      allow(provider).to receive(:get_claim).with(claim_id).and_return(base_claim)

      result = proxy.get_claim(claim_id)

      expect(result).to eq(base_claim)
      expect(provider).to have_received(:get_claim).with(claim_id)
    end

    describe 'suppress_evidence_requests transform' do
      let(:claim_with_suppressed_items) do
        {
          'data' => {
            'id' => claim_id,
            'attributes' => {
              'trackedItems' => [
                { 'id' => 1, 'displayName' => 'Item to keep' },
                { 'id' => 2, 'displayName' => 'Item in suppressed list' }
              ]
            }
          }
        }
      end

      before do
        stub_const('BenefitsClaims::Constants::SUPPRESSED_EVIDENCE_REQUESTS', ['Item in suppressed list'])
        allow(provider).to receive(:get_claim).with(claim_id).and_return(claim_with_suppressed_items)
      end

      it 'removes suppressed evidence requests when feature flag is enabled' do
        allow(Flipper).to receive(:enabled?).with(:cst_suppress_evidence_requests_website).and_return(true)

        result = proxy.get_claim(claim_id)

        tracked_items = result['data']['attributes']['trackedItems']
        expect(tracked_items.length).to eq(1)
        expect(tracked_items.first['displayName']).to eq('Item to keep')
      end

      it 'does not remove suppressed evidence requests when feature flag is disabled' do
        allow(Flipper).to receive(:enabled?).with(:cst_suppress_evidence_requests_website).and_return(false)

        result = proxy.get_claim(claim_id)

        tracked_items = result['data']['attributes']['trackedItems']
        expect(tracked_items.length).to eq(2)
      end

      it 'handles claims without tracked items' do
        claim_without_tracked_items = { 'data' => { 'id' => claim_id, 'attributes' => {} } }
        allow(provider).to receive(:get_claim).with(claim_id).and_return(claim_without_tracked_items)
        allow(Flipper).to receive(:enabled?).with(:cst_suppress_evidence_requests_website).and_return(true)

        expect { proxy.get_claim(claim_id) }.not_to raise_error
      end
    end
  end
end
