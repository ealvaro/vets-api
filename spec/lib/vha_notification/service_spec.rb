# frozen_string_literal: true

require 'rails_helper'
require 'vha_notification/service'
require 'vha_notification/configuration'
require 'vha_notification/constants'
require 'vha_notification/jwt_generator'

describe VHANotification::Service do
  subject { described_class.new }

  let(:pid) { '1234567890' }
  let(:consent_data) { true }
  let(:bearer_token) { 'test_bearer_token_12345' }

  describe '#send_mst_consent' do
    context 'with valid pid and consent_data' do
      before do
        allow(StatsD).to receive(:increment)
        allow(VHANotification::JwtGenerator).to receive(:encode_jwt).and_return(bearer_token)
        allow_any_instance_of(VHANotification::Configuration).to receive(:post_consent_update)
          .and_return(double(status: 200, body: { success: true }))
        allow(Rails.logger).to receive(:info)
      end

      it 'successfully sends consent to VHA API' do
        expect_any_instance_of(VHANotification::Configuration).to receive(:post_consent_update).with(
          pid,
          {
            source: subject.send(:source),
            vhaCommsConsent: true,
            participantId: 1_234_567_890
          },
          bearer_token
        ).and_return(double(status: 200, body: { success: true }))

        result = subject.send_mst_consent(pid, consent_data)

        expect(result[:success]).to be true
        expect(result[:response][:success]).to be true
      end

      it 'increments success metrics' do
        subject.send_mst_consent(pid, consent_data)

        expect(StatsD).to have_received(:increment).with(VHANotification::Constants::STATSD_SEND_CONSENT_SUCCESS_KEY)
        expect(StatsD).to have_received(:increment).with(VHANotification::Constants::STATSD_SEND_CONSENT_TOTAL_KEY)
        expect(StatsD).to have_received(:increment).with(VHANotification::Constants::STATSD_GET_TOKEN_SUCCESS_KEY)
      end

      it 'logs the successful consent update' do
        subject.send_mst_consent(pid, consent_data)

        expect(Rails.logger).to have_received(:info).with(
          'VHA Notification: MST consent successfully sent',
          hash_including(service: 'VHANotification')
        )
      end

      context 'when source setting is integer zero' do
        before do
          allow(Settings).to receive(:vha_notification).and_return(OpenStruct.new(source: 0))
        end

        it 'falls back to ibm source' do
          expect_any_instance_of(VHANotification::Configuration).to receive(:post_consent_update).with(
            pid,
            hash_including(source: 'ibm'),
            bearer_token
          ).and_return(double(status: 200, body: { success: true }))

          subject.send_mst_consent(pid, consent_data)
        end
      end
    end

    context 'with invalid pid' do
      it 'raises ServiceError when pid is blank' do
        expect do
          subject.send_mst_consent('', consent_data)
        end.to raise_error(VHANotification::ServiceError, 'PID is required')
      end

      it 'raises ServiceError when pid is not a string' do
        expect do
          subject.send_mst_consent(123, consent_data)
        end.to raise_error(VHANotification::ServiceError, 'PID must be a string')
      end
    end

    context 'with invalid consent_data' do
      it 'raises ServiceError when consent_data is blank' do
        expect do
          subject.send_mst_consent(pid, nil)
        end.to raise_error(VHANotification::ServiceError, 'Consent data is required')
      end

      it 'raises ServiceError when consent_data is not a boolean' do
        expect do
          subject.send_mst_consent(pid, 'invalid')
        end.to raise_error(VHANotification::ServiceError, 'Consent data must be a boolean')
      end
    end

    context 'when token retrieval fails' do
      before do
        allow(StatsD).to receive(:increment)
        allow(Rails.logger).to receive(:error)
        allow(VHANotification::JwtGenerator).to receive(:encode_jwt)
          .and_raise(StandardError.new('JWT generation failed'))
      end

      it 'raises ServiceError' do
        expect do
          subject.send_mst_consent(pid, consent_data)
        end.to raise_error(VHANotification::ServiceError, VHANotification::Constants::TOKEN_RETRIEVAL_ERROR)
      end

      it 'increments fail metrics' do
        begin
          subject.send_mst_consent(pid, consent_data)
        rescue VHANotification::ServiceError
          # Expected
        end

        expect(StatsD).to have_received(:increment).with(VHANotification::Constants::STATSD_GET_TOKEN_FAIL_KEY)
        expect(StatsD).to have_received(:increment).with(VHANotification::Constants::STATSD_SEND_CONSENT_FAIL_KEY)
        expect(StatsD).to have_received(:increment).with(VHANotification::Constants::STATSD_SEND_CONSENT_TOTAL_KEY)
      end

      it 'logs the error' do
        begin
          subject.send_mst_consent(pid, consent_data)
        rescue VHANotification::ServiceError
          # Expected
        end

        expect(Rails.logger).to have_received(:error).with(
          'VHA Notification: Failed to generate bearer token',
          hash_including(error_class: 'StandardError', error: 'JWT generation failed')
        )
      end
    end

    context 'when consent update fails' do
      before do
        allow(StatsD).to receive(:increment)
        allow(Rails.logger).to receive(:error)
        allow(VHANotification::JwtGenerator).to receive(:encode_jwt).and_return(bearer_token)
        allow_any_instance_of(VHANotification::Configuration).to receive(:post_consent_update)
          .and_raise(Faraday::ClientError.new('Consent endpoint error'))
      end

      it 'raises ServiceError' do
        expect do
          subject.send_mst_consent(pid, consent_data)
        end.to raise_error(VHANotification::ServiceError)
      end

      it 'increments fail metrics' do
        begin
          subject.send_mst_consent(pid, consent_data)
        rescue VHANotification::ServiceError
          # Expected
        end

        expect(StatsD).to have_received(:increment).with(VHANotification::Constants::STATSD_SEND_CONSENT_FAIL_KEY)
        expect(StatsD).to have_received(:increment).with(VHANotification::Constants::STATSD_SEND_CONSENT_TOTAL_KEY)
      end

      it 'logs the error details' do
        begin
          subject.send_mst_consent(pid, consent_data)
        rescue VHANotification::ServiceError
          # Expected
        end

        expect(Rails.logger).to have_received(:error).with(
          'VHA Notification: Failed to send MST consent',
          hash_including(
            error: 'Consent endpoint error',
            error_class: 'Faraday::ClientError',
            service: 'VHANotification'
          )
        )
      end
    end
  end
end
