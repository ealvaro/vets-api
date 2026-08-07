# frozen_string_literal: true

require 'rails_helper'

describe Common::Client::Base do
  module Specs
    module Common
      module Client
        class TestConfiguration < DefaultConfiguration
          def adapter_only
            true
          end
        end

        class TestService < ::Common::Client::Base
          configuration TestConfiguration
        end

        class SchemelessConfiguration < DefaultConfiguration
          def adapter_only
            true
          end

          def service_name
            'schemeless-service'
          end

          def base_path
            'example.com'
          end
        end

        class SchemelessService < ::Common::Client::Base
          configuration SchemelessConfiguration
        end

        class NilBasePathConfiguration < DefaultConfiguration
          def adapter_only
            true
          end

          def service_name
            'nil-base-path-service'
          end

          def base_path
            nil
          end
        end

        class NilBasePathService < ::Common::Client::Base
          configuration NilBasePathConfiguration
        end

        class EmptyBasePathConfiguration < DefaultConfiguration
          def adapter_only
            true
          end

          def service_name
            'empty-base-path-service'
          end

          def base_path
            ''
          end
        end

        class EmptyBasePathService < ::Common::Client::Base
          configuration EmptyBasePathConfiguration
        end

        class TestAdapterConfiguration < DefaultConfiguration
          def connection
            @conn ||= Faraday.new(nil) do |faraday|
              faraday.adapter(:test) { |stub| stub.get('/foo') { [200, {}, 'ok'] } }
            end
          end

          def service_name
            'test-adapter-service'
          end
        end

        class TestAdapterService < ::Common::Client::Base
          configuration TestAdapterConfiguration
        end
      end
    end
  end

  describe '#connection' do
    it 'raises a ConfigurationError when the base URL is missing a scheme' do
      expect { Specs::Common::Client::SchemelessService.new.send(:connection) }.to raise_error(
        Common::Client::Errors::ConfigurationError,
        /Invalid base URL for service 'schemeless-service'/
      )
    end

    it 'raises a ConfigurationError when the base URL is nil' do
      expect { Specs::Common::Client::NilBasePathService.new.send(:connection) }.to raise_error(
        Common::Client::Errors::ConfigurationError,
        /Invalid base URL for service 'nil-base-path-service'/
      )
    end

    it 'raises a ConfigurationError when the base URL is an empty string' do
      expect { Specs::Common::Client::EmptyBasePathService.new.send(:connection) }.to raise_error(
        Common::Client::Errors::ConfigurationError,
        /Invalid base URL for service 'empty-base-path-service'/
      )
    end

    it 'does not raise a ConfigurationError for test-adapter connections' do
      expect { Specs::Common::Client::TestAdapterService.new.send(:connection) }.not_to raise_error
    end
  end

  describe '#request' do
    it 'raises security error when http client is used without stripping cookies' do
      expect { Specs::Common::Client::TestService.new.send(:request, :get, '', nil) }.to raise_error(
        Common::Client::SecurityError
      )
    end
  end

  describe '#sanitize_headers!' do
    context 'where headers have symbol hash keys' do
      it 'permanentlies set any nil values to an empty string' do
        symbolized_hash = { foo: nil, bar: 'baz' }

        Specs::Common::Client::TestService.new.send('sanitize_headers!', :request, :get, '', symbolized_hash)

        expect(symbolized_hash).to eq('foo' => '', 'bar' => 'baz')
      end
    end

    context 'where headers have string hash keys' do
      it 'permanentlies set any nil values to an empty string' do
        string_hash = { 'foo' => nil, 'bar' => 'baz' }

        Specs::Common::Client::TestService.new.send('sanitize_headers!', :request, :get, '', string_hash)

        expect(string_hash).to eq('foo' => '', 'bar' => 'baz')
      end
    end

    context 'where header is an empty hash' do
      it 'returns an empty hash' do
        empty_hash = {}

        Specs::Common::Client::TestService.new.send('sanitize_headers!', :request, :get, '', empty_hash)

        expect(empty_hash).to eq({})
      end
    end
  end
end
