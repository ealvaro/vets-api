# frozen_string_literal: true

require 'rails_helper'

RSpec.describe V0::SignIn::ErrorController, type: :controller do
  describe 'GET error' do
    subject { get(:error, params:) }

    let(:params) { { error_code:, request_id:, client_id: client_config.client_id } }
    let(:error_code) { '009' }
    let(:request_id) { 'some-request-id' }
    let!(:client_config) { create(:client_config, authentication: SignIn::Constants::Auth::API) }

    it 'renders the error page HTML' do
      expect(subject.body).to include("We can't sign you in")
    end

    it 'includes the error_code' do
      expect(subject.body).to include("Error code: #{error_code}")
    end

    it 'includes the request_id' do
      expect(subject.body).to include(request_id)
    end

    it 'includes the redirect uri as the try again button' do
      expect(subject.body).to include('class="usa-button"')
      expect(subject.body).to include(client_config.logout_redirect_uri)
    end

    it 'returns ok status' do
      expect(subject).to have_http_status(:ok)
    end

    context 'when error_code is not provided' do
      let(:error_code) { nil }

      it 'defaults to the INVALID_REQUEST error code' do
        expect(subject.body).to include("Error code: #{SignIn::Constants::ErrorCode::INVALID_REQUEST}")
      end
    end

    context 'when client_id is not provided' do
      let(:params) { { error_code:, request_id: } }

      it 'does not render a button link' do
        expect(subject.body).not_to include('class="usa-button"')
      end
    end

    context 'when client_id is invalid' do
      let(:params) { { error_code:, request_id:, client_id: 'nonsense' } }

      it 'does not render a button link' do
        expect(subject.body).not_to include('class="usa-button"')
      end
    end
  end
end
