# frozen_string_literal: true

require 'rails_helper'

RSpec.describe SignIn::ClientSecretBasicCredentialsExtractor do
  describe '#perform' do
    subject(:perform) { described_class.new(request:, grant_type:, client_id:).perform }

    before { allow(Rails.logger).to receive(:info) }

    let(:expected_log_prefix) { '[SignInService] [SignIn::ClientSecretBasicCredentialsExtractor]' }
    let(:expected_log_message) { 'error' }
    let(:request) do
      env = {}
      env['HTTP_AUTHORIZATION'] = authorization_header if authorization_header.present?
      ActionDispatch::TestRequest.create(env)
    end
    let(:grant_type) { SignIn::Constants::Auth::AUTH_CODE_GRANT }
    let(:client_id) { nil }
    let(:authorization_header) { nil }

    context 'when the request is not an authorization code grant' do
      let(:grant_type) { SignIn::Constants::Auth::JWT_BEARER_GRANT }
      let(:authorization_header) do
        encoded_credentials = Base64.strict_encode64('some-client-id:some-client-secret')
        "Basic #{encoded_credentials}"
      end

      it 'returns an empty hash' do
        expect(perform).to eq({})
      end
    end

    context 'when the request does not include basic credentials' do
      it 'returns an empty hash' do
        expect(perform).to eq({})
      end
    end

    context 'when the authorization header is malformed' do
      let(:authorization_header) { 'Basic not-base64' }
      let(:expected_log_context) do
        {
          errors: 'Authorization header is malformed',
          error_code: SignIn::Constants::ErrorCode::INVALID_REQUEST,
          grant_type:
        }
      end

      it 'raises a malformed params error' do
        expect { perform }.to raise_error(SignIn::Errors::MalformedParamsError,
                                          'Authorization header is malformed')
      end

      it 'logs the extraction error' do
        expect { perform }.to raise_error(SignIn::Errors::MalformedParamsError)

        expect(Rails.logger).to have_received(:info).with("#{expected_log_prefix} #{expected_log_message}",
                                                          expected_log_context)
      end
    end

    context 'when the provided client id does not match the basic auth client id' do
      let(:client_id) { 'different-client-id' }
      let(:authorization_header) do
        encoded_credentials = Base64.strict_encode64('some-client-id:some-client-secret')
        "Basic #{encoded_credentials}"
      end
      let(:expected_log_context) do
        {
          errors: 'Client id is not valid',
          error_code: SignIn::Constants::ErrorCode::INVALID_REQUEST,
          grant_type:,
          client_id:
        }
      end

      it 'raises a malformed params error' do
        expect { perform }.to raise_error(SignIn::Errors::MalformedParamsError, 'Client id is not valid')
      end

      it 'logs the extraction error' do
        expect { perform }.to raise_error(SignIn::Errors::MalformedParamsError)

        expect(Rails.logger).to have_received(:info).with("#{expected_log_prefix} #{expected_log_message}",
                                                          expected_log_context)
      end
    end

    context 'when the authorization header contains valid credentials' do
      let(:authorization_header) do
        encoded_credentials = Base64.strict_encode64('some-client-id:some-client-secret')
        "Basic #{encoded_credentials}"
      end

      it 'returns the decoded credentials' do
        expect(perform).to eq(client_id: 'some-client-id', client_secret: 'some-client-secret')
      end
    end
  end
end
