# frozen_string_literal: true

require 'rails_helper'

RSpec.describe SafeJsonFormatter do
  subject(:formatter) { described_class.new }

  let(:logger_context) do
    double(
      host: 'test-host',
      application: 'vets-api',
      environment: 'test'
    )
  end

  def build_log(message:, exception: nil, payload: nil)
    log = SemanticLogger::Log.new('SafeJsonFormatterSpec', :error, 0)
    log.instance_variable_set(:@message, message)
    log.instance_variable_set(:@exception, exception)
    log.instance_variable_set(:@payload, payload)
    log
  end

  describe 'FM1 string-as-exception handling' do
    it 'does not raise when exception is a String' do
      log = build_log(message: 'upload failed', exception: 'string exception')

      expect { formatter.call(log, logger_context) }.not_to raise_error
    end

    it 'handles string exception and invalid UTF-8 in payload together' do
      invalid_bytes = +"\xA1x"
      invalid_bytes.force_encoding(Encoding::ASCII_8BIT)

      log = build_log(
        message: 'both failure modes',
        exception: 'string-as-exception',
        payload: { body: invalid_bytes }
      )

      parsed = JSON.parse(formatter.call(log, logger_context))

      expect(parsed.dig('exception', 'name')).to eq('String')
      expect(parsed.dig('exception', 'message')).to eq('string-as-exception')
      expect(parsed['safe_json_formatter_fallback']).to be true
      expect(parsed['payload']['body']).to eq('?x')
    end
  end

  describe 'FM2 encoding sanitization' do
    it 'does not raise JSON::GeneratorError for invalid UTF-8 payload content' do
      invalid_bytes = +"\xA1bad-data"
      invalid_bytes.force_encoding(Encoding::ASCII_8BIT)

      log = build_log(
        message: 'binary payload',
        payload: {
          body: invalid_bytes,
          nested: ['ok', { detail: invalid_bytes }]
        }
      )

      expect { formatter.call(log, logger_context) }.not_to raise_error
    end

    it 'marks logs that used the JSON fallback path' do
      invalid_bytes = +"\xA1bad-data"
      invalid_bytes.force_encoding(Encoding::ASCII_8BIT)

      log = build_log(
        message: 'binary payload',
        payload: { body: invalid_bytes }
      )

      parsed = JSON.parse(formatter.call(log, logger_context))

      expect(parsed['safe_json_formatter_fallback']).to be true
      expect(parsed['payload']['body']).to eq('?bad-data')
      expect(parsed['level']).to be_present
      expect(parsed['message']).to eq('binary payload')
    end

    it 'sanitizes invalid UTF-8 in hash keys so the fallback JSON encodes' do
      bad_key = +"\xA1meta"
      bad_key.force_encoding(Encoding::ASCII_8BIT)

      log = build_log(
        message: 'bad key',
        payload: { bad_key => 'ok' }
      )

      parsed = JSON.parse(formatter.call(log, logger_context))

      expect(parsed['safe_json_formatter_fallback']).to be true
      expect(parsed['payload'].keys).to eq(['?meta'])
      expect(parsed['payload']['?meta']).to eq('ok')
    end
  end

  describe 'standard exception serialization' do
    it 'continues to serialize a real exception' do
      error = RuntimeError.new('Exception!')
      error.set_backtrace(%w[a.rb:1 b.rb:2])
      log = build_log(message: 'failed', exception: error)

      result = formatter.call(log, logger_context)
      parsed = JSON.parse(result)

      expect(parsed.dig('exception', 'name')).to eq('RuntimeError')
      expect(parsed.dig('exception', 'message')).to eq('Exception!')
      expect(parsed).not_to have_key('safe_json_formatter_fallback')
    end
  end

  describe 'JSON fallback metadata' do
    it 'fills placeholder message when the original is absent after failure' do
      invalid_bytes = +"\xFF"
      invalid_bytes.force_encoding(Encoding::ASCII_8BIT)

      log = SemanticLogger::Log.new('SafeJsonFormatterSpec', :error, 0)
      log.instance_variable_set(:@message, nil)
      log.instance_variable_set(:@payload, { body: invalid_bytes })

      parsed = JSON.parse(formatter.call(log, logger_context))

      expect(parsed['safe_json_formatter_fallback']).to be true
      expect(parsed['message']).to eq('[SafeJsonFormatter: original message unrecoverable]')
    end
  end
end
