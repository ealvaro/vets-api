# frozen_string_literal: true

require 'rails_helper'
require 'digital_forms_api/monitor'

RSpec.describe DigitalFormsApi::Monitor do
  let(:base) { DigitalFormsApi::Monitor.new }
  let(:record) { DigitalFormsApi::Monitor::Record.new(build(:claims_evidence_submission)) }
  let(:service) { DigitalFormsApi::Monitor::Service.new }
  let(:controller) { DigitalFormsApi::Monitor::Controller.new }
  let(:uploader) { DigitalFormsApi::Monitor::Uploader.new }

  context 'base monitor functions' do
    describe '#format_message' do
      it 'returns message preceded by class name' do
        msg = base.format_message('TEST')
        expect(msg).to eq "#{subject.class}: TEST"
      end
    end

    describe '#format_tags' do
      it 'returns message preceded by class name' do
        tags = { foo: :bar, 'test' => 23 }
        tags = base.format_tags(tags)
        expect(tags).to eq ['foo:bar', 'test:23']
      end
    end
  end

  context 'Service monitor functions' do
    let(:metric) { DigitalFormsApi::Monitor::Service::METRIC }

    describe '#track_api_request' do
      it 'tracks an OK request' do
        endpoint = 'TEST'
        code = 210
        reason = 'testing ok'
        duration = 42
        call_location = 'foobar'

        tags = { method: :get, code:, endpoint: }
        formatted_tags = ['method:get', 'code:210', 'endpoint:TEST']
        message = "#{service.class}: #{code} #{reason}"

        kwargs = { call_location:, reason:, duration:, tags: formatted_tags, **tags }
        expect(service).to receive(:track_request).with(:info, message, metric, **kwargs)
        expect(StatsD).to receive(:measure).with("#{metric}.duration", duration, tags: anything)

        service.track_api_request(:get, endpoint, code, reason, duration, call_location:)
      end

      it 'tracks an Error request' do
        endpoint = 'TEST'
        code = 404
        reason = 'testing 404'
        duration = 42
        call_location = 'foobar'

        tags = { method: :get, code:, endpoint: }
        formatted_tags = ['method:get', 'code:404', 'endpoint:TEST']
        message = "#{service.class}: #{code} #{reason}"

        kwargs = { call_location:, reason:, duration:, tags: formatted_tags, **tags }
        expect(service).to receive(:track_request).with(:error, message, metric, **kwargs)
        expect(StatsD).to receive(:measure).with("#{metric}.duration", duration, tags: anything)

        service.track_api_request(:get, endpoint, code, reason, duration, call_location:)
      end
    end

    describe '#track_template_cache' do
      it 'tracks template cache status' do
        call_location = 'foobar'
        tags = { endpoint: 'templates', form_id: '21-686c', cache_status: 'hit' }
        formatted_tags = ['endpoint:templates', 'form_id:21-686c', 'cache_status:hit']
        message = "#{service.class}: template cache hit"
        kwargs = { call_location:, tags: formatted_tags, **tags }

        expect(StatsD).to receive(:increment).with(DigitalFormsApi::Monitor::Service::TEMPLATE_FETCH_METRIC, tags:)
        expect(service).to receive(:track_request).with(
          :info,
          message,
          DigitalFormsApi::Monitor::Service::TEMPLATE_CACHE_METRIC,
          **kwargs
        )

        service.track_template_cache('21-686c', 'hit', call_location:)
      end
    end

    describe '#track_schema_cache' do
      it 'tracks schema cache status' do
        call_location = 'foobar'
        tags = { endpoint: 'schemas', form_id: '21-686c', cache_status: 'hit' }
        formatted_tags = ['endpoint:schemas', 'form_id:21-686c', 'cache_status:hit']
        message = "#{service.class}: schema cache hit"
        kwargs = { call_location:, tags: formatted_tags, **tags }

        expect(StatsD).to receive(:increment).with(DigitalFormsApi::Monitor::Service::SCHEMA_FETCH_METRIC, tags:)
        expect(service).to receive(:track_request).with(
          :info,
          message,
          DigitalFormsApi::Monitor::Service::SCHEMA_CACHE_METRIC,
          **kwargs
        )

        service.track_schema_cache('21-686c', 'hit', call_location:)
      end
    end
  end

  context 'Controller monitor functions' do
    describe '#track_show' do
      it 'tracks a successful show status' do
        call_location = 'foobar'
        formatted_tags = [
          'endpoint:submissions_show',
          'http_status:200',
          'form_id:21-686c',
          'template_version:0.2.0'
        ]
        message = "#{controller.class}: submissions#show 200"
        kwargs = {
          call_location:,
          tags: formatted_tags,
          endpoint: 'submissions_show',
          http_status: 200,
          submission_id: 'abc123',
          form_id: '21-686c',
          template_version: '0.2.0'
        }

        expect(StatsD).not_to receive(:measure)
        expect(controller).to receive(:track_request).with(:info, message,
                                                           DigitalFormsApi::Monitor::Controller::SHOW_METRIC, **kwargs)

        controller.track_show(
          http_status: 200,
          submission_id: 'abc123',
          form_id: '21-686c',
          call_location:,
          template_version: '0.2.0'
        )
      end

      it 'tracks show duration with enriched error tags' do
        call_location = 'foobar'
        expected_tags = {
          endpoint: 'submissions_show',
          http_status: 500,
          form_id: '21-686c',
          error_class: 'RuntimeError',
          failure_stage: 'fetch_template',
          error_source: 'unexpected_error'
        }
        formatted_tags = [
          'endpoint:submissions_show',
          'http_status:500',
          'form_id:21-686c',
          'error_class:RuntimeError',
          'failure_stage:fetch_template',
          'error_source:unexpected_error'
        ]
        message = "#{controller.class}: submissions#show 500"
        kwargs = {
          call_location:,
          tags: formatted_tags,
          endpoint: 'submissions_show',
          http_status: 500,
          submission_id: 'abc123',
          form_id: '21-686c',
          error_class: 'RuntimeError',
          failure_stage: 'fetch_template',
          error_source: 'unexpected_error',
          duration_ms: 42
        }

        expect(StatsD).to receive(:measure).with(
          "#{DigitalFormsApi::Monitor::Controller::SHOW_METRIC}.duration",
          42,
          tags: expected_tags
        )
        expect(controller).to receive(:track_request).with(
          :error,
          message,
          DigitalFormsApi::Monitor::Controller::SHOW_METRIC,
          **kwargs
        )

        controller.track_show(
          http_status: 500,
          submission_id: 'abc123',
          form_id: '21-686c',
          call_location:,
          error_class: 'RuntimeError',
          failure_stage: 'fetch_template',
          error_source: 'unexpected_error',
          duration_ms: 42
        )
      end
    end

    describe '#track_template_version' do
      it 'tracks template version metric' do
        call_location = 'foobar'
        formatted_tags = ['endpoint:submissions_show', 'form_id:21-686c', 'template_version:0.2.0']
        message = "#{controller.class}: template version 0.2.0"
        kwargs = {
          call_location:,
          tags: formatted_tags,
          endpoint: 'submissions_show',
          form_id: '21-686c',
          template_version: '0.2.0'
        }

        expect(controller).to receive(:track_request).with(
          :info,
          message,
          DigitalFormsApi::Monitor::Controller::TEMPLATE_VERSION_METRIC,
          **kwargs
        )

        controller.track_template_version(form_id: '21-686c', template_version: '0.2.0', call_location:)
      end

      it 'does not track when version is blank' do
        expect(controller).not_to receive(:track_request)

        controller.track_template_version(form_id: '21-686c', template_version: nil)
      end
    end
  end
end
