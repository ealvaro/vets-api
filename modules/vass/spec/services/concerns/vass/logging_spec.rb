# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Vass::Logging do
  let(:service_class) do
    Class.new do
      include Vass::Logging

      def self.name
        'Vass::TestService'
      end

      def fire_event(...)
        log_vass_event(...)
      end

      def fire_error(...)
        log_vass_error(...)
      end

      def fire_write(...)
        write_vass_log(...)
      end
    end
  end

  let(:service_instance) { service_class.new }

  let(:controller_class) do
    Class.new do
      include Vass::Logging

      def controller_name
        'sessions'
      end

      def action_name
        'request_otp'
      end

      def fire_event(...)
        log_vass_event(...)
      end

      def fire_error(...)
        log_vass_error(...)
      end
    end
  end

  let(:controller_instance) { controller_class.new }

  describe '#log_vass_event' do
    context 'when called from a service class' do
      it 'logs with class name' do
        expect(Rails.logger).to receive(:info).with(a_string_including(
                                                      '"service":"vass"',
                                                      '"class_name":"Vass::TestService"'
                                                    ))

        service_instance.fire_event('test_event')
      end

      it 'includes the event key' do
        expect(Rails.logger).to receive(:info).with(a_string_including('"event":"cache_miss"'))

        service_instance.fire_event('cache_miss')
      end

      it 'does not include error_code key' do
        json_output = nil
        allow(Rails.logger).to receive(:info) { |message| json_output = message }

        service_instance.fire_event('test_event')

        expect(json_output).not_to include('"error_code"')
      end

      it 'does not include action key outside controller context' do
        json_output = nil
        allow(Rails.logger).to receive(:info) { |message| json_output = message }

        service_instance.fire_event('test_event')

        expect(json_output).not_to include('"action"')
      end

      it 'includes timestamp in ISO8601 format' do
        freeze_time = Time.zone.parse('2026-01-20 12:00:00 UTC')

        Timecop.freeze(freeze_time) do
          expect(Rails.logger).to receive(:info).with(a_string_including(
                                                        '"timestamp":"2026-01-20T12:00:00Z"'
                                                      ))

          service_instance.fire_event('test_event')
        end
      end

      it 'includes optional vass_uuid when provided' do
        expect(Rails.logger).to receive(:info).with(a_string_including(
                                                      '"vass_uuid":"test-uuid-123"'
                                                    ))

        service_instance.fire_event('test_event', vass_uuid: 'test-uuid-123')
      end

      it 'includes additional metadata' do
        expect(Rails.logger).to receive(:info).with(a_string_including(
                                                      '"correlation_id":"corr-123"',
                                                      '"extra":"data"'
                                                    ))

        service_instance.fire_event('test_event', correlation_id: 'corr-123', extra: 'data')
      end

      it 'defaults to info log level' do
        expect(Rails.logger).to receive(:info)
        service_instance.fire_event('test_event')
      end

      it 'respects a custom log level' do
        expect(Rails.logger).to receive(:warn)
        service_instance.fire_event('test_event', level: :warn)
      end
    end

    context 'when called from a controller' do
      it 'includes controller and action from the controller context' do
        expect(Rails.logger).to receive(:info).with(a_string_including(
                                                      '"controller":"sessions"',
                                                      '"action":"request_otp"'
                                                    ))

        controller_instance.fire_event('otp_generated')
      end

      it 'includes event alongside action' do
        json_output = nil
        allow(Rails.logger).to receive(:info) { |message| json_output = message }

        controller_instance.fire_event('otp_generated')

        parsed = JSON.parse(json_output)
        expect(parsed['action']).to eq('request_otp')
        expect(parsed['event']).to eq('otp_generated')
        expect(parsed).not_to have_key('error_code')
      end

      it 'does not include class_name field when controller_name is present' do
        json_output = nil
        allow(Rails.logger).to receive(:info) { |message| json_output = message }

        controller_instance.fire_event('otp_generated')

        expect(json_output).not_to include('"class_name"')
      end
    end
  end

  describe '#log_vass_error' do
    context 'when called from a service class' do
      it 'logs with class name' do
        expect(Rails.logger).to receive(:error).with(a_string_including(
                                                       '"service":"vass"',
                                                       '"class_name":"Vass::TestService"'
                                                     ))

        service_instance.fire_error('parse_failed')
      end

      it 'includes the error_code key' do
        expect(Rails.logger).to receive(:error).with(a_string_including('"error_code":"parse_failed"'))

        service_instance.fire_error('parse_failed')
      end

      it 'does not include event key' do
        json_output = nil
        allow(Rails.logger).to receive(:error) { |message| json_output = message }

        service_instance.fire_error('parse_failed')

        expect(json_output).not_to include('"event"')
      end

      it 'defaults to error log level' do
        expect(Rails.logger).to receive(:error)
        service_instance.fire_error('parse_failed')
      end

      it 'respects a custom log level' do
        expect(Rails.logger).to receive(:warn)
        service_instance.fire_error('rate_limited', level: :warn)
      end

      it 'includes additional metadata' do
        expect(Rails.logger).to receive(:error).with(a_string_including(
                                                       '"correlation_id":"corr-123"',
                                                       '"error_class":"TestError"'
                                                     ))

        service_instance.fire_error('test_error', correlation_id: 'corr-123', error_class: 'TestError')
      end
    end

    context 'when called from a controller' do
      it 'includes controller and action from the controller context' do
        expect(Rails.logger).to receive(:error).with(a_string_including(
                                                       '"controller":"sessions"',
                                                       '"action":"request_otp"'
                                                     ))

        controller_instance.fire_error('missing_contact_info')
      end

      it 'includes error_code alongside action' do
        json_output = nil
        allow(Rails.logger).to receive(:error) { |message| json_output = message }

        controller_instance.fire_error('missing_contact_info')

        parsed = JSON.parse(json_output)
        expect(parsed['action']).to eq('request_otp')
        expect(parsed['error_code']).to eq('missing_contact_info')
        expect(parsed).not_to have_key('event')
      end
    end
  end

  describe 'reserved key protection' do
    it 'does not allow metadata to override action in controller context' do
      json_output = nil
      allow(Rails.logger).to receive(:error) { |message| json_output = message }

      controller_instance.fire_error('test_error', action: 'spoofed')

      parsed = JSON.parse(json_output)
      expect(parsed['action']).to eq('request_otp')
    end

    it 'does not allow metadata to override service' do
      json_output = nil
      allow(Rails.logger).to receive(:info) { |message| json_output = message }

      service_instance.fire_event('test_event', service: 'spoofed')

      parsed = JSON.parse(json_output)
      expect(parsed['service']).to eq('vass')
    end

    it 'does not allow metadata to override controller' do
      json_output = nil
      allow(Rails.logger).to receive(:info) { |message| json_output = message }

      controller_instance.fire_event('test_event', controller: 'spoofed')

      parsed = JSON.parse(json_output)
      expect(parsed['controller']).to eq('sessions')
    end

    it 'does not allow log_vass_error to inject an event key via metadata' do
      json_output = nil
      allow(Rails.logger).to receive(:error) { |message| json_output = message }

      service_instance.fire_error('test_error', event: 'spoofed')

      parsed = JSON.parse(json_output)
      expect(parsed).not_to have_key('event')
      expect(parsed['error_code']).to eq('test_error')
    end

    it 'does not allow log_vass_event to inject an error_code key via metadata' do
      json_output = nil
      allow(Rails.logger).to receive(:info) { |message| json_output = message }

      service_instance.fire_event('test_event', error_code: 'spoofed')

      parsed = JSON.parse(json_output)
      expect(parsed).not_to have_key('error_code')
      expect(parsed['event']).to eq('test_event')
    end

    it 'does not allow metadata to override class_name in service context' do
      json_output = nil
      allow(Rails.logger).to receive(:info) { |message| json_output = message }

      service_instance.fire_event('test_event', class_name: 'spoofed')

      parsed = JSON.parse(json_output)
      expect(parsed['class_name']).to eq('Vass::TestService')
    end
  end

  describe 'error handling' do
    it 'raises ArgumentError when both event and error_code are provided' do
      expect do
        service_instance.fire_write(event: 'test_event', error_code: 'test_error')
      end.to raise_error(ArgumentError, /Provide event or error_code, not both/)
    end

    it 'raises AuditLogError on JSON::GeneratorError' do
      allow(Rails.logger).to receive(:info).and_raise(JSON::GeneratorError, 'Invalid encoding')

      expect do
        service_instance.fire_event('test_event')
      end.to raise_error(Vass::Errors::AuditLogError, /Failed to write audit log/)
    end

    it 'raises AuditLogError on Encoding::UndefinedConversionError' do
      allow(Rails.logger).to receive(:info).and_raise(Encoding::UndefinedConversionError, 'Bad bytes')

      expect do
        service_instance.fire_event('test_event')
      end.to raise_error(Vass::Errors::AuditLogError, /Failed to write audit log/)
    end
  end

  describe 'JSON output format' do
    it 'outputs valid JSON from log_vass_event' do
      json_output = nil
      allow(Rails.logger).to receive(:info) { |message| json_output = message }

      service_instance.fire_event('test_event', custom_field: 'value')

      expect { JSON.parse(json_output) }.not_to raise_error
    end

    it 'outputs valid JSON from log_vass_error' do
      json_output = nil
      allow(Rails.logger).to receive(:error) { |message| json_output = message }

      service_instance.fire_error('test_error', custom_field: 'value')

      expect { JSON.parse(json_output) }.not_to raise_error
    end

    it 'includes all expected fields for events' do
      json_output = nil
      allow(Rails.logger).to receive(:info) { |message| json_output = message }

      service_instance.fire_event('test_event', vass_uuid: 'uuid-123', extra: 'data')

      parsed = JSON.parse(json_output)
      expect(parsed).to include(
        'service' => 'vass',
        'event' => 'test_event',
        'class_name' => 'Vass::TestService',
        'vass_uuid' => 'uuid-123',
        'extra' => 'data'
      )
      expect(parsed).to have_key('timestamp')
    end

    it 'includes all expected fields for errors' do
      json_output = nil
      allow(Rails.logger).to receive(:error) { |message| json_output = message }

      service_instance.fire_error('test_error', vass_uuid: 'uuid-456', extra: 'info')

      parsed = JSON.parse(json_output)
      expect(parsed).to include(
        'service' => 'vass',
        'error_code' => 'test_error',
        'class_name' => 'Vass::TestService',
        'vass_uuid' => 'uuid-456',
        'extra' => 'info'
      )
      expect(parsed).to have_key('timestamp')
    end
  end
end
