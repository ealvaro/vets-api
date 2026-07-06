# frozen_string_literal: true

require_relative '../../../rails_helper'

RSpec.describe 'AccreditedRepresentativePortal::V0::Apidocs', type: :request do
  describe 'GET /accredited_representative_portal/v0/apidocs' do
    it 'returns 200 and valid JSON without authentication' do
      get '/accredited_representative_portal/v0/apidocs'

      expect(response).to have_http_status(:ok)
      expect(response.content_type).to include('application/json')

      body = JSON.parse(response.body)
      expect(body).to include('openapi', 'info', 'paths')
    end
  end
end
