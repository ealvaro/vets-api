# frozen_string_literal: true

require 'rails_helper'
require 'logging/helper/data_scrubber'

RSpec.describe PIIFilteringFormatter do
  subject(:formatter) { described_class.new }

  let(:redaction) { '[REDACTED]' }
  let(:logger_context) do
    double(
      host: 'test-host',
      application: 'vets-api',
      environment: 'test'
    )
  end

  def build_log(message:, level: :info, exception: nil, payload: nil)
    log = SemanticLogger::Log.new('PIIFilteringFormatterSpec', level, 0)
    log.instance_variable_set(:@message, message)
    log.instance_variable_set(:@exception, exception)
    log.instance_variable_set(:@payload, payload)
    log
  end

  def format_log(**)
    JSON.parse(formatter.call(build_log(**), logger_context))
  end

  describe 'PII scrubbing in structured metadata' do
    # Covers all 11 DataScrubber pattern types
    let(:pii_payload) do
      {
        ssn: '123-45-6789',
        email: 'user@example.com',
        icn: '1234567890V123456',
        edipi: '1234567890',
        phone: '(555) 123-4567',
        credit_card: '4444-4444-4444-4444',
        zip_code: '12345-6789',
        birth_date: '01/15/1990',
        va_file_number: 'C12345678',
        routing_number: '123456789',
        participant_id: '12345678'
      }
    end

    it 'redacts all PII patterns in payload values' do
      parsed = format_log(message: 'User action', payload: pii_payload)

      pii_payload.each_key do |key|
        next if key == :icn # ICN is intentionally not scrubbed — it is needed for Datadog monitoring

        expect(parsed['payload'][key.to_s]).to eq(redaction), "expected #{key} to be redacted"
      end

      expect(parsed['payload']['icn']).to eq('1234567890V123456')
    end

    it 'leaves string-only log messages unchanged' do
      parsed = format_log(message: 'User action with SSN 123-45-6789')

      expect(parsed['message']).to eq('User action with SSN 123-45-6789')
      expect(parsed).not_to have_key('payload')
    end

    it 'preserves non-PII payload values' do
      parsed = format_log(message: 'Operation', payload: { service: 'claims', status: 'ok' })

      expect(parsed['payload']).to eq('service' => 'claims', 'status' => 'ok')
    end

    it 'redacts PII in nested hash payloads' do
      parsed = format_log(
        message: 'User action',
        payload: {
          user: {
            name: 'John Doe',
            contact: { email: 'john@example.com', phone: '555-123-4567' }
          }
        }
      )

      expect(parsed['payload']['user']['name']).to eq('John Doe')
      expect(parsed['payload']['user']['contact']['email']).to eq(redaction)
      expect(parsed['payload']['user']['contact']['phone']).to eq(redaction)
    end
  end

  describe 'safe_keys per-call allowlist' do
    it 'preserves specified fields and removes safe_keys from output' do
      parsed = format_log(
        message: 'User action',
        payload: {
          ssn: '123-45-6789',
          email: 'user@example.com',
          safe_keys: [:ssn]
        }
      )

      expect(parsed['payload']['ssn']).to eq('123-45-6789')
      expect(parsed['payload']['email']).to eq(redaction)
      expect(parsed['payload']).not_to have_key('safe_keys')
    end

    it 'accepts safe_keys as strings' do
      parsed = format_log(
        message: 'User action',
        payload: {
          custom_field: '555-123-4567',
          unsafe_field: '123-45-6789',
          safe_keys: ['custom_field']
        }
      )

      expect(parsed['payload']['custom_field']).to eq('555-123-4567')
      expect(parsed['payload']['unsafe_field']).to eq(redaction)
    end

    it 'supports safe_keys when key is provided as a string' do
      parsed = format_log(
        message: 'User action',
        payload: {
          ssn: '123-45-6789',
          email: 'user@example.com',
          'safe_keys' => ['ssn']
        }
      )

      expect(parsed['payload']['ssn']).to eq('123-45-6789')
      expect(parsed['payload']['email']).to eq(redaction)
      expect(parsed['payload']).not_to have_key('safe_keys')
    end

    it 'applies safe_keys to matching keys at any nesting depth' do
      parsed = format_log(
        message: 'User action',
        payload: {
          custom_safe_field: '555-123-4567',
          nested: {
            custom_safe_field: 'jane@example.com',
            unsafe_nested: '123-45-6789'
          },
          safe_keys: [:custom_safe_field]
        }
      )

      expect(parsed['payload']['custom_safe_field']).to eq('555-123-4567')
      expect(parsed['payload']['nested']['custom_safe_field']).to eq('jane@example.com')
      expect(parsed['payload']['nested']['unsafe_nested']).to eq(redaction)
    end
  end

  describe 'log output format' do
    it 'preserves JSON structure with level, message, and payload keys' do
      parsed = format_log(message: 'test message', payload: { key: 'value' })

      expect(parsed['level']).to eq('info')
      expect(parsed['message']).to eq('test message')
      expect(parsed['payload']).to eq('key' => 'value')
    end
  end

  describe 'SafeJsonFormatter behavior preservation' do
    it 'does not raise when exception is a String' do
      log = build_log(message: 'upload failed', exception: 'string exception')

      expect { formatter.call(log, logger_context) }.not_to raise_error
    end

    it 'handles string exception and invalid UTF-8 in payload together' do
      invalid_bytes = +"\xA1x"
      invalid_bytes.force_encoding(Encoding::ASCII_8BIT)

      parsed = format_log(
        message: 'both failure modes',
        exception: 'string-as-exception',
        payload: { body: invalid_bytes }
      )

      expect(parsed.dig('exception', 'name')).to eq('String')
      expect(parsed.dig('exception', 'message')).to eq('string-as-exception')
      expect(parsed['safe_json_formatter_fallback']).to be true
      expect(parsed['payload']['body']).to eq('?x')
    end

    it 'continues to serialize a real exception' do
      error = RuntimeError.new('Exception!')
      error.set_backtrace(%w[a.rb:1 b.rb:2])
      log = build_log(message: 'failed', exception: error)

      parsed = JSON.parse(formatter.call(log, logger_context))

      expect(parsed.dig('exception', 'name')).to eq('RuntimeError')
      expect(parsed.dig('exception', 'message')).to eq('Exception!')
      expect(parsed).not_to have_key('safe_json_formatter_fallback')
    end
  end
end
