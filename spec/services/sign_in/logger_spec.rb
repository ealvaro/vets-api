# frozen_string_literal: true

require 'rails_helper'

RSpec.describe SignIn::Logger do
  let(:logger) { SignIn::Logger.new(prefix:) }
  let(:prefix) { 'some-logger-prefix' }
  let(:user_account) { create(:user_account) }
  let(:expected_logger_message) { "[SignInService] [#{prefix}] #{message}" }
  let(:message) { 'some-message' }
  let(:attribute) { 'some-attribute' }

  before do
    allow(Rails.logger).to receive(:info)
  end

  describe '#info' do
    subject { logger.info(message, attributes) }

    let(:attributes) { { attribute: } }

    it 'create a Rails info log with expected values' do
      expect(Rails.logger).to receive(:info).with(expected_logger_message, attributes)
      subject
    end
  end

  describe '#error' do
    subject do
      logger.error(message, exception:, context:)
    end

    let(:context) { { attribute: } }
    let(:exception_message) { 'something went wrong' }
    let(:exception) { StandardError.new(exception_message) }

    let(:expected_payload) do
      context.merge(
        errors: exception_message,
        error_code:
      )
    end

    let(:error_code) { SignIn::Constants::ErrorCode::INVALID_REQUEST }

    it 'logs an info message with payload' do
      expect(Rails.logger).to receive(:info)
        .with(expected_logger_message, expected_payload)

      subject
    end

    context 'when exception responds to code' do
      let(:error_code) { 'CUSTOM_ERROR' }
      let(:exception) { SignIn::Errors::StandardError.new(message: exception_message, code: error_code) }

      it 'uses the exception code' do
        expect(Rails.logger).to receive(:info)
          .with(expected_logger_message, expected_payload)

        subject
      end
    end

    context 'when context is empty' do
      let(:context) { {} }

      it 'still logs with error details' do
        expect(Rails.logger).to receive(:info)
          .with(expected_logger_message, expected_payload)

        subject
      end
    end
  end
end
