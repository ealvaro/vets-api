# frozen_string_literal: true

require 'rails_helper'
require_relative '../../../rails_helper'

RSpec.describe 'ClaimsApi::V3::Veterans::526', type: :request do
  describe '#submit' do
    let(:icn) { '1012861229V078999' } # Janet Moore
    let(:submit_path) { "/services/claims/v3/veterans/#{icn}/526" }

    it 'returns 401 Unauthorized when no auth token is provided' do
      post submit_path

      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns 501 Not Implemented when the auth wall is bypassed' do
      allow_any_instance_of(ClaimsApi::V3::Veterans::DisabilityCompensationController)
        .to receive(:authenticate).and_return(true)

      post submit_path

      expect(response).to have_http_status(:not_implemented)
      parsed = JSON.parse(response.body)
      expect(parsed['errors']).to be_an(Array)
      expect(parsed['errors'].first['status']).to eq('501')
      expect(parsed['errors'].first['title']).to eq('Not Implemented')
    end
  end
end
