# frozen_string_literal: true

require 'rails_helper'
require 'oracle_health/o_auth/service'
require 'oracle_health/o_auth/errors'

RSpec.describe OracleHealth::OAuth::Service do
  describe '#get_token' do
    subject { described_class.new.get_token }

    let(:logging_prefix) { '[OracleHealth][Service]' }
    let(:client_id) { 'test_client_id' }
    let(:client_secret) { 'test_client_secret' }
    let(:token_path) { 'tenants/00224df3-b096-4cdb-852c-cbc83c0d3b06/protocols/oauth2/profiles/smart-v1/token' }
    let(:base_path) { 'https://authorization.cerner.ehr.gov' }
    let(:expected_response_body) { { access_token:, scope:, token_type:, expires_in: } }
    let(:scope) { 'system/Patient.read system/Patient.write' }
    let(:token_type) { 'Bearer' }
    let(:expires_in) { 570 }
    let(:access_token) { 'some-access-token' }
    let(:config) { instance_double(OracleHealth::OAuth::Configuration) }
    let(:statsd_key_prefix) { 'api.oracle_health.oauth' }
    let(:grant_type) { 'client_credentials' }
    let(:expected_request_body) { URI.encode_www_form(grant_type:, scope:) }
    let(:expected_request_headers) do
      {
        'Authorization' => "Basic #{Base64.strict_encode64("#{client_id}:#{client_secret}")}",
        'Content-Type' => 'application/x-www-form-urlencoded',
        'Accept' => 'application/json'
      }
    end

    before do
      allow(Rails.logger).to receive(:info)
      allow(Rails.logger).to receive(:error)
      allow(StatsD).to receive(:increment)
      allow(IdentitySettings.oracle_health.oauth).to receive_messages(client_id:, client_secret:,
                                                                      uri: base_path)
      allow(OracleHealth::OAuth::Configuration).to receive(:new).and_return(config)
    end

    context 'when the request is successful' do
      it 'logs the request' do
        VCR.use_cassette('oracle_health/get_token_success_200') do
          subject
          expect(Rails.logger).to have_received(:info).with("#{logging_prefix} get_token request")
        end
      end

      it 'returns the expected response body' do
        VCR.use_cassette('oracle_health/get_token_success_200') do
          expect(subject).to eq(expected_response_body)
        end
      end

      it 'sends the expected headers' do
        VCR.use_cassette('oracle_health/get_token_success_200') do
          subject
          expect(a_request(:post, "#{base_path}/#{token_path}")
                 .with(headers: expected_request_headers)).to have_been_made
        end
      end

      it 'sends the expected body' do
        VCR.use_cassette('oracle_health/get_token_success_200') do
          subject
          expect(a_request(:post, "#{base_path}/#{token_path}")
                 .with(body: expected_request_body)).to have_been_made
        end
      end
    end

    context 'when request gives an error' do
      context 'with invalid_client error' do
        it 'logs the error' do
          VCR.use_cassette('oracle_health/get_token_invalid_client_error_401') do
            expect { subject }.to raise_error(OracleHealth::OAuth::Errors::InvalidClientError)
            expect(Rails.logger).to have_received(:error).with("#{logging_prefix} get_token invalid_client",
                                                               hash_including(:error_message, :body, :status))
          end
        end

        it 'raises an OracleHealth::OAuth::Errors::InvalidClientError' do
          VCR.use_cassette('oracle_health/get_token_invalid_client_error_401') do
            expect { subject }.to raise_error(OracleHealth::OAuth::Errors::InvalidClientError)
          end
        end

        it 'increments StatsD' do
          VCR.use_cassette('oracle_health/get_token_invalid_client_error_401') do
            expect { subject }.to raise_error(OracleHealth::OAuth::Errors::InvalidClientError)
            expect(StatsD).to have_received(:increment).with("#{statsd_key_prefix}.get_token.failure",
                                                             tags: ['error:invalid_client'])
          end
        end
      end

      context 'with invalid_scope error' do
        it 'logs the error' do
          VCR.use_cassette('oracle_health/get_token_invalid_scope_error_400') do
            expect { subject }.to raise_error(OracleHealth::OAuth::Errors::InvalidScopeError)
            expect(Rails.logger).to have_received(:error).with("#{logging_prefix} get_token invalid_scope",
                                                               hash_including(:error_message, :body, :status))
          end
        end

        it 'raises an OracleHealth::OAuth::Errors::InvalidScopeError' do
          VCR.use_cassette('oracle_health/get_token_invalid_scope_error_400') do
            expect { subject }.to raise_error(OracleHealth::OAuth::Errors::InvalidScopeError)
          end
        end

        it 'increments StatsD' do
          VCR.use_cassette('oracle_health/get_token_invalid_scope_error_400') do
            expect { subject }.to raise_error(OracleHealth::OAuth::Errors::InvalidScopeError)
            expect(StatsD).to have_received(:increment).with("#{statsd_key_prefix}.get_token.failure",
                                                             tags: ['error:invalid_scope'])
          end
        end
      end

      context 'with nil response body' do
        it 'logs the error' do
          VCR.use_cassette('oracle_health/get_token_nil_response_body_error_400') do
            expect { subject }.to raise_error(OracleHealth::OAuth::Errors::TokenError)
            expect(Rails.logger).to have_received(:error).with("#{logging_prefix} get_token ",
                                                               hash_including(:error_message, :status, body: nil))
          end
        end

        it 'raises an OracleHealth::OAuth::Errors::TokenError' do
          VCR.use_cassette('oracle_health/get_token_nil_response_body_error_400') do
            expect { subject }.to raise_error(OracleHealth::OAuth::Errors::TokenError)
          end
        end

        it 'increments StatsD' do
          VCR.use_cassette('oracle_health/get_token_nil_response_body_error_400') do
            expect { subject }.to raise_error(OracleHealth::OAuth::Errors::TokenError)
            expect(StatsD).to have_received(:increment).with("#{statsd_key_prefix}.get_token.failure", tags: ['error:'])
          end
        end
      end

      context 'with 5XX error' do
        it 'logs the error' do
          VCR.use_cassette('oracle_health/get_token_error_500') do
            expect { subject }.to raise_error(OracleHealth::OAuth::Errors::ServiceUnavailableError)
            expect(Rails.logger).to have_received(:error).with("#{logging_prefix} get_token ",
                                                               hash_including(:error_message, :body, :status))
          end
        end

        it 'raises an OracleHealth::OAuth::Errors::TokenError' do
          VCR.use_cassette('oracle_health/get_token_error_500') do
            expect { subject }.to raise_error(OracleHealth::OAuth::Errors::ServiceUnavailableError)
          end
        end

        it 'increments StatsD' do
          VCR.use_cassette('oracle_health/get_token_error_500') do
            expect { subject }.to raise_error(OracleHealth::OAuth::Errors::ServiceUnavailableError)
            expect(StatsD).to have_received(:increment).with("#{statsd_key_prefix}.get_token.failure", tags: ['error:'])
          end
        end
      end

      context 'with unknown error' do
        it 'logs the error' do
          VCR.use_cassette('oracle_health/get_token_unknown_error') do
            expect { subject }.to raise_error(StandardError)
            expect(Rails.logger).to have_received(:error).with("#{logging_prefix} get_token Forbidden",
                                                               hash_including(:error_message))
          end
        end

        it 'raises a StandardError' do
          VCR.use_cassette('oracle_health/get_token_unknown_error') do
            expect { subject }.to raise_error(StandardError)
          end
        end

        it 'increments StatsD' do
          VCR.use_cassette('oracle_health/get_token_unknown_error') do
            expect { subject }.to raise_error(StandardError)
            expect(StatsD).to have_received(:increment).with("#{statsd_key_prefix}.get_token.failure",
                                                             tags: ['error:Forbidden'])
          end
        end
      end
    end
  end
end
