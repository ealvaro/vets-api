# frozen_string_literal: true

require 'rails_helper'

require 'digital_forms_api/service/templates'

require_relative 'shared/service'

RSpec.describe DigitalFormsApi::Service::Templates do
  let(:service) { described_class.new }
  let(:form_id) { '21-686c' }
  let(:template_cache_key) { described_class.cache_key(form_id) }
  let(:memory_store) { ActiveSupport::Cache.lookup_store(:memory_store) }
  let(:monitor) { instance_double(DigitalFormsApi::Monitor::Service, track_template_cache: true) }

  let(:template_body) { { 'template' => 'data' } }
  let(:faraday_env) { instance_double(Faraday::Env, body: template_body, status: 200) }

  before do
    allow(Rails).to receive(:cache).and_return(memory_store)
    allow(service).to receive(:monitor).and_return(monitor)
    Rails.cache.clear
  end

  it_behaves_like 'a DigitalFormsApi::Service class'

  describe '#get' do
    it 'performs a GET via class method' do
      allow(DigitalFormsApi::Service::Templates).to receive(:new).and_return service

      path = "forms/#{form_id}/template"
      expect(service).to receive(:perform).with(:get, path, {}, {}).and_return(faraday_env)
      DigitalFormsApi::Service::Templates.get(form_id)
    end
  end

  describe '#template' do
    context 'when template is not cached' do
      it 'performs a GET request to the forms endpoint' do
        expect(service).to receive(:perform).with(:get, "forms/#{form_id}/template", {}, {}).and_return(faraday_env)
        expect(monitor).to receive(:track_template_cache).with(form_id, 'miss')
        service.template(form_id)
      end

      it 'caches only the response body' do
        allow(service).to receive(:perform).and_return(faraday_env)

        service.template(form_id)

        cached = Rails.cache.read(template_cache_key)
        expect(cached).to eq(template_body)
      end

      it 'returns the parsed body from the API' do
        allow(service).to receive(:perform).and_return(faraday_env)

        result = service.template(form_id)

        expect(result).to eq(template_body)
      end
    end

    context 'when template is called twice' do
      it 'only calls the upstream service once' do
        expect(service).to receive(:perform)
          .with(:get, "forms/#{form_id}/template", {}, {})
          .once
          .and_return(faraday_env)

        first_result  = service.template(form_id)
        second_result = service.template(form_id)

        expect(first_result).to eq(template_body)
        expect(second_result).to eq(template_body)
      end
    end

    context 'when template is cached' do
      it 'returns the cached body without making an API request' do
        Rails.cache.write(template_cache_key, template_body)

        expect(service).not_to receive(:perform)
        expect(monitor).to receive(:track_template_cache).with(form_id, 'hit')

        result = service.template(form_id)

        expect(result).to eq(template_body)
      end
    end
  end
end
