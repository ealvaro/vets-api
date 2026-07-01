# frozen_string_literal: true

require 'rails_helper'

RSpec.describe PIIFilteringColorFormatter do
  subject(:formatter) { described_class.new }

  let(:redaction) { '[REDACTED]' }
  let(:logger_context) do
    double(
      host: 'test-host',
      application: 'vets-api',
      environment: 'development'
    )
  end

  def build_log(message:, level: :info, name: 'Rails', exception: nil, payload: nil)
    log = SemanticLogger::Log.new(name, level, 0)
    log.instance_variable_set(:@message, message)
    log.instance_variable_set(:@exception, exception)
    log.instance_variable_set(:@payload, payload)
    log
  end

  def format_log(**kwargs)
    formatter.call(build_log(**kwargs), logger_context)
  end

  def strip_ansi(text)
    text.gsub(/\e\[[\d;]*m/, '')
  end

  describe 'human-readable output' do
    it 'uses the SemanticLogger color/default line format' do
      output = strip_ansi(format_log(message: 'test', payload: { key: 'value' }))

      expect(output).to include('Rails -- test --')
      expect(output).to include(':key => "value"')
    end

    it 'does not emit JSON' do
      output = format_log(message: 'test', payload: { key: 'value' })

      expect(output).not_to include('"payload"')
      expect { JSON.parse(output) }.to raise_error(JSON::ParserError)
    end
  end

  describe 'PII scrubbing in structured metadata' do
    it 'redacts PII in payload values' do
      output = strip_ansi(
        format_log(
          message: 'User action',
          payload: { ssn: '123-45-6789', email: 'user@example.com' }
        )
      )

      expect(output).to include(':ssn => "[REDACTED]"')
      expect(output).to include(':email => "[REDACTED]"')
      expect(output).not_to include('123-45-6789')
      expect(output).not_to include('user@example.com')
    end

    it 'leaves string-only log messages unchanged' do
      output = strip_ansi(format_log(message: 'User action with SSN 123-45-6789'))

      expect(output).to include('Rails -- User action with SSN 123-45-6789')
      expect(output).not_to include('-- {')
    end

    it 'redacts PII in nested hash payloads' do
      output = strip_ansi(
        format_log(
          message: 'User action',
          payload: {
            user: {
              name: 'John Doe',
              contact: { email: 'john@example.com', phone: '555-123-4567' }
            }
          }
        )
      )

      expect(output).to include(':name => "John Doe"')
      expect(output).to include(':email => "[REDACTED]"')
      expect(output).to include(':phone => "[REDACTED]"')
      expect(output).not_to include('john@example.com')
      expect(output).not_to include('555-123-4567')
    end
  end

  describe 'safe_keys per-call allowlist' do
    it 'preserves specified fields and removes safe_keys from output' do
      output = strip_ansi(
        format_log(
          message: 'User action',
          payload: {
            ssn: '123-45-6789',
            email: 'user@example.com',
            safe_keys: [:ssn]
          }
        )
      )

      expect(output).to include(':ssn => "123-45-6789"')
      expect(output).to include(':email => "[REDACTED]"')
      expect(output).not_to include(':safe_keys')
    end

    it 'supports safe_keys when key is provided as a string' do
      output = strip_ansi(
        format_log(
          message: 'User action',
          payload: {
            ssn: '123-45-6789',
            email: 'user@example.com',
            'safe_keys' => ['ssn']
          }
        )
      )

      expect(output).to include(':ssn => "123-45-6789"')
      expect(output).to include(':email => "[REDACTED]"')
      expect(output).not_to include(':safe_keys')
    end

    it 'applies safe_keys to matching keys at any nesting depth' do
      output = strip_ansi(
        format_log(
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
      )

      expect(output).to include(':custom_safe_field => "555-123-4567"')
      expect(output).to include(':custom_safe_field => "jane@example.com"')
      expect(output).to include(':unsafe_nested => "[REDACTED]"')
      expect(output).not_to include('123-45-6789')
    end
  end
end
