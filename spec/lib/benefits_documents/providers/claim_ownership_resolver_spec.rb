# frozen_string_literal: true

require 'rails_helper'
require 'benefits_documents/providers/claim_ownership_resolver'

RSpec.describe BenefitsDocuments::Providers::ClaimOwnershipResolver do
  subject(:resolver) { described_class.new }

  describe '#provider_for' do
    it 'uses an explicit supported provider param' do
      expect(resolver.provider_for(provider: 'ivc_champva', claim_id: '123')).to eq(:ivc_champva)
    end

    it 'uses snake_case upload metadata for CHAMPVA uploads' do
      params = {
        claim_id: '123',
        upload_metadata: {
          upload_destination_key: 'ivc_champva_supporting_documents'
        }
      }

      expect(resolver.provider_for(params)).to eq(:ivc_champva)
    end

    it 'uses camelCase upload metadata for Lighthouse uploads' do
      params = {
        claim_id: '123',
        uploadMetadata: {
          uploadDestinationKey: 'benefits_claims'
        }
      }

      expect(resolver.provider_for(params)).to eq(:lighthouse)
    end

    it 'uses CHAMPVA form records for nonnumeric claim IDs' do
      allow(IvcChampvaForm).to receive(:exists?)
        .with(form_uuid: 'champva-claim-uuid')
        .and_return(true)

      expect(resolver.provider_for(claim_id: 'champva-claim-uuid')).to eq(:ivc_champva)
    end

    it 'does not look up numeric claim IDs as CHAMPVA form UUIDs' do
      expect(IvcChampvaForm).not_to receive(:exists?)

      expect(resolver.provider_for(claim_id: '123')).to eq(:lighthouse)
    end

    it 'falls back to Lighthouse when ownership is unclear' do
      allow(IvcChampvaForm).to receive(:exists?)
        .with(form_uuid: 'unknown-claim')
        .and_return(false)

      expect(resolver.provider_for(claim_id: 'unknown-claim')).to eq(:lighthouse)
    end

    it 'falls back to Lighthouse for unsupported explicit providers' do
      expect(resolver.provider_for(provider: 'unknown', claim_id: '123')).to eq(:lighthouse)
    end
  end
end
