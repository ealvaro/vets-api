# frozen_string_literal: true

require 'rails_helper'

RSpec.describe MyHealth::V2::Concerns::ErrorHandler, type: :controller do
  # Minimal test controller that includes the concern
  controller(ApplicationController) do
    include MyHealth::V2::Concerns::ErrorHandler

    skip_before_action :authenticate

    def index
      error = Common::Exceptions::UpstreamPartialFailure.new(
        failed_sources: ['vista'],
        failure_details: [{ source: 'vista', code: 'exception', diagnostics: '502 Bad Gateway' }]
      )
      handle_error(error, resource_name: 'allergies', api_type: 'SCDF')
    end
  end

  before do
    routes.draw { get 'index' => 'anonymous#index' }
    allow(Rails.logger).to receive(:error)
    allow(Datadog::Tracing).to receive(:active_span).and_return(nil)
  end

  describe '#handle_error with UpstreamPartialFailure' do
    it 'renders 502 Bad Gateway with failed sources detail' do
      get :index

      expect(response).to have_http_status(:bad_gateway)
      body = JSON.parse(response.body)
      expect(body['errors'].first['code']).to eq('502')
      expect(body['errors'].first['title']).to eq('SCDF Upstream Partial Failure')
      expect(body['errors'].first['detail']).to include('vista')
    end
  end
end
