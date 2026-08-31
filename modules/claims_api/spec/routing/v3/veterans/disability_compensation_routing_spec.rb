# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Claims API v3 disability compensation routing', type: :routing do
  let(:controller) { 'claims_api/v3/veterans/disability_compensation' }

  describe 'submit' do
    it 'routes POST to disability_compensation#submit' do
      expect(post('/services/claims/v3/veterans/526')).to route_to(
        format: 'json',
        controller:,
        action: 'submit'
      )
    end
  end

  describe 'generatePDF' do
    it 'routes POST to disability_compensation#generatePDF' do
      expect(post('/services/claims/v3/veterans/526/generatePDF')).to route_to(
        format: 'json',
        controller:,
        action: 'generate_pdf'
      )
    end
  end

  describe 'upload_supporting_documents' do
    let(:claim_id) { '600134256' }

    it 'routes POST to disability_compensation#upload_supporting_documents' do
      expect(post("/services/claims/v3/veterans/526/#{claim_id}/attachments")).to route_to(
        format: 'json',
        controller:,
        action: 'upload_supporting_documents',
        id: claim_id
      )
    end
  end
end
