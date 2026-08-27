# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Mobile::V0::VeteranVerification::Service do
  let(:service) { described_class.new }

  let(:icn) { '1234567890V123456' }
  let(:lighthouse_client_id) { 'test_client_id' }
  let(:lighthouse_rsa_key_path) { 'spec/fixtures/mock_rsa_key.pem' }

  describe '#get_vet_verification_status' do
    context 'when icn is blank' do
      it 'raises ArgumentError for nil icn' do
        expect { service.get_vet_verification_status(nil) }.to raise_error(ArgumentError, 'icn is required')
      end

      it 'raises ArgumentError for an empty string icn' do
        expect { service.get_vet_verification_status('') }.to raise_error(ArgumentError, 'icn is required')
      end

      it 'does not call out to Lighthouse' do
        config = instance_double(VeteranVerification::Configuration)
        allow(service).to receive(:config).and_return(config)
        expect(config).not_to receive(:get)

        expect { service.get_vet_verification_status(nil) }.to raise_error(ArgumentError)
      end

      it 'increments only the mobile total StatsD key, not fail, since the guard bypasses that rescue branch' do
        expect(StatsD).to receive(:increment).with('api.lighthouse.veteran_verification_status.mobile.total')
        expect(StatsD).not_to receive(:increment).with('api.lighthouse.veteran_verification_status.mobile.fail')

        expect { service.get_vet_verification_status(nil) }.to raise_error(ArgumentError)
      end
    end

    context 'when icn is present' do
      let(:config) { instance_double(VeteranVerification::Configuration) }
      let(:raw_response) { instance_double(Faraday::Response, body: response_body) }

      before do
        allow(service).to receive(:config).and_return(config)
      end

      context 'and Lighthouse returns a confirmed status' do
        let(:response_body) do
          {
            'data' => {
              'attributes' => {
                'veteran_status' => 'confirmed'
              }
            }
          }
        end

        it 'calls the status endpoint with the icn' do
          expect(config).to receive(:get)
            .with("status/#{icn}", lighthouse_client_id, lighthouse_rsa_key_path, {})
            .and_return(raw_response)

          service.get_vet_verification_status(icn, lighthouse_client_id, lighthouse_rsa_key_path)
        end

        it 'returns the response body' do
          allow(config).to receive(:get).and_return(raw_response)

          result = service.get_vet_verification_status(icn, lighthouse_client_id, lighthouse_rsa_key_path)

          expect(result).to eq(response_body)
        end

        it 'logs the mobile-specific confirmed message' do
          allow(config).to receive(:get).and_return(raw_response)

          expect(Rails.logger).to receive(:info).with(
            'Mobile Vet Verification Status Success: confirmed', { confirmed: true }
          )

          service.get_vet_verification_status(icn, lighthouse_client_id, lighthouse_rsa_key_path)
        end

        it 'increments only the mobile total StatsD key' do
          allow(config).to receive(:get).and_return(raw_response)

          expect(StatsD).to receive(:increment).with('api.lighthouse.veteran_verification_status.mobile.total')
          expect(StatsD).not_to receive(:increment).with('api.lighthouse.veteran_verification_status.mobile.fail')

          service.get_vet_verification_status(icn, lighthouse_client_id, lighthouse_rsa_key_path)
        end
      end

      context 'and Lighthouse returns a not-confirmed status' do
        let(:response_body) do
          {
            'data' => {
              'attributes' => {
                'veteran_status' => 'not confirmed',
                'not_confirmed_reason' => 'NOT_TITLE_38'
              }
            }
          }
        end

        it 'logs the mobile-specific not-confirmed message with the reason' do
          allow(config).to receive(:get).and_return(raw_response)

          expect(Rails.logger).to receive(:info).with(
            'Mobile Vet Verification Status Success: not confirmed',
            { not_confirmed: true, not_confirmed_reason: 'NOT_TITLE_38' }
          )

          service.get_vet_verification_status(icn, lighthouse_client_id, lighthouse_rsa_key_path)
        end

        it 'sets a message/title/status on the response for the frontend' do
          allow(config).to receive(:get).and_return(raw_response)

          result = service.get_vet_verification_status(icn, lighthouse_client_id, lighthouse_rsa_key_path)

          expect(result['data']['message']).to be_present
          expect(result['data']['title']).to be_present
          expect(result['data']['status']).to be_present
        end
      end

      context 'and the Lighthouse call raises' do
        before do
          allow(config).to receive(:get).and_raise(Common::Client::Errors::ClientError.new('boom'))
        end

        it 'calls handle_error with the correct endpoint' do
          expect(service).to receive(:handle_error).with(
            instance_of(Common::Client::Errors::ClientError),
            lighthouse_client_id,
            'status'
          )

          service.get_vet_verification_status(icn, lighthouse_client_id, lighthouse_rsa_key_path)
        end

        it 'increments both the mobile fail and total StatsD keys' do
          allow(service).to receive(:handle_error)

          expect(StatsD).to receive(:increment).with('api.lighthouse.veteran_verification_status.mobile.fail')
          expect(StatsD).to receive(:increment).with('api.lighthouse.veteran_verification_status.mobile.total')

          service.get_vet_verification_status(icn, lighthouse_client_id, lighthouse_rsa_key_path)
        end
      end
    end
  end
end
