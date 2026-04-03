# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'AskVAApi::V0::Diagnostics', type: :request do
  let(:diagnostics_path) { '/ask_va_api/v0/diagnostics' }

  describe 'GET #show' do
    before do
      allow(Crm::Service).to receive(:crm_env).and_return({ 'test' => 'iris-dev' })
      allow(Settings).to receive(:vsp_environment).and_return('test')
      get diagnostics_path
    end

    it 'returns http status ok with crm_environment' do
      body = JSON.parse(response.body)
      expect(response).to have_http_status(:ok)
      expect(body['crm_environment']).to eq('iris-dev')
    end
  end
end
