# frozen_string_literal: true

require 'rails_helper'

require 'digital_forms_api/service/base'

require_relative 'shared/service'

RSpec.describe DigitalFormsApi::Service::Base do
  let(:service) { described_class.new }

  it_behaves_like 'a DigitalFormsApi::Service class'

  describe '#build_context' do
    it 'returns a hash with the given keys and a nested tags key' do
      result = service.send(:build_context, form_id: '21-686c', submission_id: 'abc123')

      expect(result).to eq(
        form_id: '21-686c',
        submission_id: 'abc123',
        tags: { form_id: '21-686c', submission_id: 'abc123' }
      )
    end

    it 'returns an empty tags hash when no keys are provided' do
      result = service.send(:build_context)

      expect(result).to eq(tags: {})
    end
  end

  describe '#parse_error' do
    it 'extracts reason from error body messages array' do
      error = double(
        'error',
        message: 'fallback',
        body: {
          'messages' => [{ 'text' => 'First message' }, { 'text' => 'Second message' }]
        }
      )

      reason = service.send(:parse_error, error)

      expect(reason).to eq('First message')
    end

    it 'falls back to body message when messages array is absent' do
      error = double('error', message: 'fallback', body: { 'message' => 'Body message' })

      reason = service.send(:parse_error, error)

      expect(reason).to eq('Body message')
    end

    it 'falls back to body message when messages is not an array' do
      error = double('error', message: 'fallback', body: { 'messages' => 'nope', 'message' => 'Body message' })

      reason = service.send(:parse_error, error)

      expect(reason).to eq('Body message')
    end

    it 'falls back to error.message when body is a non-Hash (e.g. string)' do
      error = double('error', message: 'Raw error text', body: 'not a hash')

      reason = service.send(:parse_error, error)

      expect(reason).to eq('Raw error text')
    end

    it 'falls back to error.message when body is nil' do
      error = double('error', message: 'Error with nil body', body: nil)

      reason = service.send(:parse_error, error)

      expect(reason).to eq('Error with nil body')
    end
  end
end
