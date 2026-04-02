# frozen_string_literal: true

require 'rails_helper'

require 'digital_forms_api/service/base'
require 'digital_forms_api/validation'

RSpec.describe DigitalFormsApi::Validation do
  let(:jsonpath) { "#{DigitalFormsApi::MODULE_PATH}/schema/openapi.json" }
  let(:openapi) { JSON.parse(File.read(jsonpath)) }
  let(:service) { DigitalFormsApi::Service::Base.new }

  let(:cache_key) { 'digital_forms_api:openapi' }
  let(:schema_body) { { 'schema' => 'data' } }
  let(:faraday_env) { instance_double(Faraday::Env, body: schema_body, status: 200) }

  let(:memory_store) { ActiveSupport::Cache.lookup_store(:memory_store) }

  before do
    allow(DigitalFormsApi::Service::Base).to receive(:new).and_return(service)

    allow(Rails).to receive(:cache).and_return(memory_store)
    Rails.cache.clear
  end

  after do
    Rails.cache.clear
  end

  describe '#openapi' do
    it 'performs a GET request for the openapi.json' do
      expect(service).to receive(:perform).with(:get, /openapi.json$/, {}, {})
      subject.openapi
    end

    it 'caches only the response body' do
      allow(service).to receive(:perform).and_return(faraday_env)

      subject.openapi

      cached = Rails.cache.read(cache_key)
      expect(cached).to eq(schema_body)
    end

    it 'returns the cached body without making an API request' do
      Rails.cache.write(cache_key, schema_body)

      expect(service).not_to receive(:perform)

      result = subject.openapi

      expect(result).to eq(schema_body)
    end

    it 'returns the stored hardcopy if the request errors' do
      expect(service).to receive(:perform).and_raise RuntimeError

      schema = subject.openapi
      expect(schema).to eq(openapi)
    end
  end

  describe '#validate_submission_request' do
    let(:payload) do
      { data: 'TEST' }
    end
    let(:metadata) do
      {
        formId: '99t-12345',
        veteranId: '123456789v12345',
        claimantId: 'another-identifier',
        epCode: '99999999',
        claimLabel: '99999999DPEBNAJRE'
      }
    end

    before do
      allow(service).to receive(:perform).and_return(openapi)
    end

    it 'returns a valid request body' do
      expected = metadata.deep_dup
      expected[:claimantId] = { identifierType: 'PARTICIPANTID', value: expected[:claimantId] }
      expected[:veteranId] = { identifierType: 'PARTICIPANTID', value: expected[:veteranId] }

      expected = { envelope: expected.merge({ payload: }) }

      result = subject.validate_submission_request(payload, metadata)
      expect(result).to eq(expected)
    end

    it 'raises a JSON::Schema::ValidationError' do
      invalid = { test: '23' }
      expect { subject.validate_submission_request(invalid, invalid) }.to raise_error JSON::Schema::ValidationError
    end
  end
end
