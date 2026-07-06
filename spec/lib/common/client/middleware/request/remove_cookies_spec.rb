# frozen_string_literal: true

require 'rails_helper'
require 'puma'
require 'rack'

describe Common::Client::Middleware::Request::RemoveCookies do
  module Specs
    module RemoveCookies
      class TestConfiguration < Specs::Common::Client::DefaultConfiguration
        def use_example_path
          false
        end
      end

      class TestService < ::Common::Client::Base
        configuration TestConfiguration
      end
    end
  end
  # This test requires the creation of a new thread via Puma's internal threading
  describe '#request' do
    let!(:puma_server) do
      app = proc do |env|
        cookie_header = env['HTTP_COOKIE'].to_s
        cookies = cookie_header.strip.empty? ? [] : cookie_header.split(/;\s*/)
        [200, { 'Set-Cookie' => 'foo=bar', 'Content-Type' => 'application/json' }, [cookies.to_json]]
      end

      server = Puma::Server.new(app)
      server.add_tcp_listener('127.0.0.1', Specs::RemoveCookies::TestConfiguration.instance.port)
      server.run
      server
    end

    after do
      VCR.configure do |c|
        c.allow_http_connections_when_no_cassette = false
      end

      puma_server.stop(true)
    end

    it 'strips cookies' do
      VCR.configure do |c|
        c.allow_http_connections_when_no_cassette = true
      end

      Timeout.timeout(5) do
        loop do
          break if Specs::RemoveCookies::TestService.new.send(:request, :get, '', nil).status == 200
        rescue Common::Client::Errors::ClientError
          next
        end
      end

      expect(Specs::RemoveCookies::TestService.new.send(:request, :get, '', nil).body).to eq('[]')
    end
  end
end
