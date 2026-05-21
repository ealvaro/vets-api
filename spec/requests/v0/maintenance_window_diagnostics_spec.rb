# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'V0::MaintenanceWindowDiagnostics', type: :request do
  describe 'GET /v0/maintenance_windows/diagnostics' do
    it 'returns probe results and isolates the bad entries' do
      probe = [
        { setting_name: 'good', service_id: 'GOOD123', status: 200 },
        { setting_name: 'bad', service_id: 'BAD123', status: 404 },
        { setting_name: 'empty', service_id: nil, status: nil }
      ]
      allow_any_instance_of(PagerDuty::ServicesClient).to receive(:probe).and_return(probe)

      get '/v0/maintenance_windows/diagnostics'

      assert_response :success
      body = JSON.parse(response.body)
      expect(body['results'].size).to eq(3)
      expect(body['bad'].size).to eq(1)
      expect(body['bad'].first['setting_name']).to eq('bad')
      expect(body['bad'].first['service_id']).to eq('BAD123')
      expect(body['bad'].first['status']).to eq(404)
    end
  end
end
