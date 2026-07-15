# frozen_string_literal: true

require 'rails_helper'

RSpec.describe SignIn::ClientSecretValidator do
  describe '#perform' do
    subject(:perform) { described_class.new(client_id:, client_secret:, client_config:).perform }

    shared_examples 'a client secret validation failure' do
      it 'raises a client secret invalid error' do
        expect { perform }.to raise_error(expected_error, expected_error_message)
      end

      it 'logs the validation error' do
        expect { perform }.to raise_error(expected_error)

        expect(Rails.logger).to have_received(:info).with("#{expected_log_prefix} #{expected_log_message}",
                                                          expected_log_context)
      end
    end

    before { allow(Rails.logger).to receive(:info) }

    let(:expected_log_prefix) { '[SignInService] [SignIn::ClientSecretValidator]' }
    let(:expected_log_message) { 'error' }
    let(:stored_client_secret) { 'expected-client-secret' }
    let(:client_config) { create(:client_config, client_secret: stored_client_secret, auth_method: 'client_secret') }
    let(:client_id) { client_config.client_id }
    let(:client_secret) { stored_client_secret }
    let(:expected_error) { SignIn::Errors::ClientSecretInvalidError }
    let(:expected_error_message) { 'Client secret is not valid' }

    context 'when the provided client id is nil' do
      let(:client_id) { nil }
      let(:expected_log_context) do
        {
          errors: expected_error_message,
          error_code: SignIn::Constants::ErrorCode::INVALID_REQUEST,
          client_config_client_id: client_config.client_id
        }
      end

      it_behaves_like 'a client secret validation failure'
    end

    context 'when the provided client secret is nil' do
      let(:client_secret) { nil }
      let(:expected_log_context) do
        {
          errors: expected_error_message,
          error_code: SignIn::Constants::ErrorCode::INVALID_REQUEST,
          client_id:,
          client_config_client_id: client_config.client_id
        }
      end

      it_behaves_like 'a client secret validation failure'
    end

    context 'when the client config is nil' do
      let(:client_id) { 'some-client-id' }
      let(:client_config) { nil }
      let(:expected_log_context) do
        {
          errors: expected_error_message,
          error_code: SignIn::Constants::ErrorCode::INVALID_REQUEST,
          client_id:
        }
      end

      it_behaves_like 'a client secret validation failure'
    end

    context 'when the provided client id does not match the client config' do
      let(:client_id) { 'some-other-client-id' }
      let(:expected_log_context) do
        {
          errors: expected_error_message,
          error_code: SignIn::Constants::ErrorCode::INVALID_REQUEST,
          client_id:,
          client_config_client_id: client_config.client_id
        }
      end

      it_behaves_like 'a client secret validation failure'
    end

    context 'when the provided client secret does not match the client config' do
      let(:client_secret) { 'wrong-client-secret' }
      let(:expected_log_context) do
        {
          errors: expected_error_message,
          error_code: SignIn::Constants::ErrorCode::INVALID_REQUEST,
          client_id:,
          client_config_client_id: client_config.client_id
        }
      end

      it_behaves_like 'a client secret validation failure'
    end

    context 'when the provided client id and client secret match the client config' do
      it 'returns true' do
        expect(perform).to be(true)
      end
    end
  end
end
