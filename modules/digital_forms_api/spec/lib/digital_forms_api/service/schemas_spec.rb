# frozen_string_literal: true

require 'rails_helper'

require 'digital_forms_api/service/schemas'

require_relative 'shared/service'

RSpec.describe DigitalFormsApi::Service::Schemas do
  let(:service) { described_class.new }
  let(:form_id) { '21-686c' }
  let(:schema_cache_key) { described_class.cache_key(form_id) }
  let(:memory_store) { ActiveSupport::Cache.lookup_store(:memory_store) }
  let(:monitor) { instance_double(DigitalFormsApi::Monitor::Service, track_schema_cache: true) }

  let(:schema_body) { { 'schema' => 'data' } }
  let(:faraday_env) { instance_double(Faraday::Env, body: schema_body, status: 200) }

  before do
    allow(Rails).to receive(:cache).and_return(memory_store)
    allow(service).to receive(:monitor).and_return(monitor)
    Rails.cache.clear
  end

  it_behaves_like 'a DigitalFormsApi::Service class'

  describe '#get' do
    it 'performs a GET via class method' do
      allow(DigitalFormsApi::Service::Schemas).to receive(:new).and_return service

      path = "forms/#{form_id}/schema"
      expect(service).to receive(:perform).with(:get, path, {}, {}).and_return(faraday_env)
      DigitalFormsApi::Service::Schemas.get(form_id)
    end
  end

  describe '#schema' do
    context 'when schema is not cached' do
      it 'performs a GET request to the forms endpoint' do
        expect(service).to receive(:perform).with(:get, "forms/#{form_id}/schema", {}, {}).and_return(faraday_env)
        expect(monitor).to receive(:track_schema_cache).with(form_id, 'miss')
        service.schema(form_id)
      end

      it 'caches only the response body' do
        allow(service).to receive(:perform).and_return(faraday_env)

        service.schema(form_id)

        cached = Rails.cache.read(schema_cache_key)
        expect(cached).to eq(schema_body)
      end

      it 'returns the parsed body from the API' do
        allow(service).to receive(:perform).and_return(faraday_env)

        result = service.schema(form_id)

        expect(result).to eq(schema_body)
      end
    end

    context 'when schema is called twice' do
      it 'only calls the upstream service once' do
        expect(service).to receive(:perform)
          .with(:get, "forms/#{form_id}/schema", {}, {})
          .once
          .and_return(faraday_env)

        first_result  = service.schema(form_id)
        second_result = service.schema(form_id)

        expect(first_result).to eq(schema_body)
        expect(second_result).to eq(schema_body)
      end
    end

    context 'when schema is cached' do
      it 'returns the cached body without making an API request' do
        Rails.cache.write(schema_cache_key, schema_body)

        expect(service).not_to receive(:perform)
        expect(monitor).to receive(:track_schema_cache).with(form_id, 'hit')

        result = service.schema(form_id)

        expect(result).to eq(schema_body)
      end
    end
  end
end
