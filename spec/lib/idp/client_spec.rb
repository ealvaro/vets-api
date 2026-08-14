# frozen_string_literal: true

require 'rails_helper'
require 'idp/client'

RSpec.describe Idp::Client do
  describe '#initialize' do
    include ActiveSupport::Testing::TimeHelpers

    before do
      allow(Settings).to receive(:dig).and_call_original
    end

    it 'raises an error when base_url is not configured' do
      allow(Settings).to receive(:dig).with(:cave, :idp, :base_url).and_return(nil)
      allow(Settings).to receive(:dig).with(:cave, :idp, :connect_url).and_return(nil)
      allow(Settings).to receive(:dig).with(:cave, :idp, :timeout).and_return(nil)

      expect { described_class.new(base_url: nil) }
        .to raise_error(Idp::Error, /IDP base URL is not configured/)
    end

    it 'uses settings for base_url, connect_url, and timeout' do
      allow(Settings).to receive(:dig).with(:cave, :idp, :base_url).and_return('https://settings-idp.example.com')
      allow(Settings).to receive(:dig).with(:cave, :idp, :connect_url).and_return('https://vpce-idp.example.com')
      allow(Settings).to receive(:dig).with(:cave, :idp, :timeout).and_return(22)

      client = described_class.new

      expect(client.send(:base_url)).to eq('https://settings-idp.example.com')
      expect(client.send(:connect_url)).to eq('https://vpce-idp.example.com')
      expect(client.send(:timeout)).to eq(22)
    end

    it 'uses the default timeout when none is provided' do
      client = described_class.new(base_url: 'https://example.com')

      expect(client.send(:timeout)).to eq(Idp::Client::DEFAULT_TIMEOUT)
    end

    it 'accepts a custom timeout' do
      client = described_class.new(base_url: 'https://example.com', timeout: 30)

      expect(client.send(:timeout)).to eq(30)
    end

    it 'raises an error when connect_url is set without a logical base_url' do
      allow(Settings).to receive(:dig).with(:cave, :idp, :base_url).and_return(nil)

      expect { described_class.new(connect_url: 'https://vpce-idp.example.com') }
        .to raise_error(Idp::Error, /IDP base URL is not configured/)
    end

    it 'coerces string timeouts to integers' do
      client = described_class.new(base_url: 'https://example.com', timeout: '30')

      expect(client.send(:timeout)).to eq(30)
    end

    it 'falls back to the default timeout for invalid timeout values' do
      client = described_class.new(base_url: 'https://example.com', timeout: 'not-a-number')

      expect(client.send(:timeout)).to eq(Idp::Client::DEFAULT_TIMEOUT)
    end

    it 'resolves the connect_url hostname to a TCP destination IP' do
      allow(Resolv).to receive(:getaddresses).with('vpce-idp.example.com').and_return(['10.0.0.10'])

      client = described_class.new(
        base_url: 'https://logical-idp.example.com/stg/api/v1/doc',
        connect_url: 'https://vpce-idp.example.com/stg/api/v1/doc'
      )

      expect(client.send(:connect_ipaddr)).to eq('10.0.0.10')
    end

    it 'raises an error when connect_url cannot be resolved' do
      allow(Resolv).to receive(:getaddresses).with('vpce-idp.example.com').and_return([])

      client = described_class.new(
        base_url: 'https://logical-idp.example.com/stg/api/v1/doc',
        connect_url: 'https://vpce-idp.example.com/stg/api/v1/doc'
      )

      expect { client.send(:connect_ipaddr) }
        .to raise_error(Idp::Error, /IDP connect URL could not be resolved/)
    end

    it 'does not retry DNS during the connect resolution cooldown' do
      allow(Resolv).to receive(:getaddresses).with('vpce-idp.example.com').and_return([])

      client = described_class.new(
        base_url: 'https://logical-idp.example.com/stg/api/v1/doc',
        connect_url: 'https://vpce-idp.example.com/stg/api/v1/doc'
      )

      expect { client.send(:connect_ipaddr) }
        .to raise_error(Idp::Error, /IDP connect URL could not be resolved/)
      expect { client.send(:connect_ipaddr) }
        .to raise_error(Idp::Error, /IDP connect URL could not be resolved/)
      expect(Resolv).to have_received(:getaddresses).once
    end

    it 'retries DNS after the connect resolution cooldown' do
      allow(Resolv).to receive(:getaddresses).with('vpce-idp.example.com')
                                             .and_return([], ['10.0.0.10'])

      client = described_class.new(
        base_url: 'https://logical-idp.example.com/stg/api/v1/doc',
        connect_url: 'https://vpce-idp.example.com/stg/api/v1/doc'
      )

      expect { client.send(:connect_ipaddr) }
        .to raise_error(Idp::Error, /IDP connect URL could not be resolved/)

      travel_to(Time.zone.now + Idp::Client::CONNECT_RESOLVE_RETRY_SECONDS + 1) do
        expect(client.send(:connect_ipaddr)).to eq('10.0.0.10')
      end

      expect(Resolv).to have_received(:getaddresses).twice
    end

    it 'logs a warning when connect_url resolution raises SocketError' do
      allow(Resolv).to receive(:getaddresses).with('vpce-idp.example.com').and_raise(SocketError, 'lookup failed')
      allow(Rails.logger).to receive(:warn)

      client = described_class.new(
        base_url: 'https://logical-idp.example.com/stg/api/v1/doc',
        connect_url: 'https://vpce-idp.example.com/stg/api/v1/doc'
      )

      expect { client.send(:connect_ipaddr) }
        .to raise_error(Idp::Error, /IDP connect URL could not be resolved/)
      expect(Rails.logger).to have_received(:warn).with(
        '[Idp::Client] connect_url resolution failed',
        hash_including(
          connect_url: 'https://vpce-idp.example.com/stg/api/v1/doc',
          connect_destination_host: 'vpce-idp.example.com',
          error_class: 'SocketError',
          error_message: 'lookup failed'
        )
      )
    end

    it 'applies the resolved TCP destination to the Net::HTTP connection' do
      allow(Resolv).to receive(:getaddresses).with('vpce-idp.example.com').and_return(['10.0.0.10'])

      client = described_class.new(
        base_url: 'https://logical-idp.example.com/stg/api/v1/doc',
        connect_url: 'https://vpce-idp.example.com/stg/api/v1/doc'
      )
      http = double('Net::HTTP')
      allow(http).to receive(:respond_to?).with(:ipaddr=).and_return(true)

      expect(http).to receive(:ipaddr=).with('10.0.0.10')

      client.send(:apply_connect_override, http)
    end
  end

  describe '.breakers_service' do
    it 'returns a Breakers::Service named IDP' do
      service = described_class.breakers_service

      expect(service).to be_a(Breakers::Service)
      expect(service.name).to eq(Idp::Client::SERVICE_NAME)
    end

    it 'matches requests by the IDP service_name' do
      service = described_class.breakers_service

      expect(service.handles_request?(request_env: nil, service_name: 'IDP')).to be(true)
      expect(service.handles_request?(request_env: nil, service_name: 'OTHER')).to be(false)
    end
  end

  describe '#connection' do
    subject(:connection) { described_class.new(base_url: 'https://idp.example.com').send(:connection) }

    it 'includes breakers middleware first with the IDP service_name' do
      expect(connection.builder.handlers.first).to eq(Breakers::UptimeMiddleware)
      expect(connection.app).to be_a(Breakers::UptimeMiddleware)
      expect(connection.app.service_name).to eq(Idp::Client::SERVICE_NAME)
    end

    it 'uses the net_http adapter' do
      expect(connection.builder.adapter).to eq(Faraday::Adapter::NetHttp)
    end
  end

  describe 'IDP endpoints' do
    subject(:client) do
      described_class.new(base_url:, connect_url:, timeout:, hmac_key_id:, hmac_secret:)
    end

    let(:base_url) { 'https://idp.example.com' }
    let(:connect_url) { nil }
    let(:timeout) { 15 }
    let(:hmac_key_id) { 'idp-hmac-v1' }
    let(:hmac_secret) { 'super-secret' }
    let(:user_id) { 'user-account-uuid-123' }
    let(:request_url) { base_url }

    def valid_signed_headers?(request, user_id:, hmac_key_id:)
      headers = request.headers.transform_keys { |key| key.to_s.downcase }
      headers['x-idp-user-id'] == user_id &&
        headers['x-idp-key-id'] == hmac_key_id &&
        headers['x-idp-timestamp'].to_s.match?(/\A\d+\z/) &&
        headers['x-idp-signature'].to_s.match?(/\A[0-9a-f]{64}\z/)
    end

    def request_query(request)
      CGI.parse(URI.parse(request.uri.to_s).query.to_s).transform_values(&:first)
    end

    it 'sends intake request and returns parsed payload' do
      stub_request(:post, "#{request_url}/intake")
        .with(body: { pdf_b64: 'ZmlsZQ==' }.to_json)
        .to_return(status: 200, body: { id: 'abc123' }.to_json, headers: { 'Content-Type' => 'application/json' })

      response = client.intake(file_name: 'test.pdf', pdf_base64: 'ZmlsZQ==', user_id:)

      expect(response).to eq('id' => 'abc123')
      expect(WebMock).to have_requested(:post, "#{request_url}/intake").with { |request|
        request.headers['X-Filename'] == 'test.pdf' &&
          request.headers['Content-Type'].to_s.include?('application/json') &&
          valid_signed_headers?(request, user_id:, hmac_key_id:)
      }
    end

    it 'sends status request and returns parsed payload' do
      stub_request(:get, %r{#{Regexp.escape(request_url)}/status}).to_return(
        status: 200,
        body: { scan_status: 'completed' }.to_json,
        headers: { 'Content-Type' => 'application/json' }
      )

      response = client.status('abc123', user_id:)

      expect(response).to eq('scan_status' => 'completed')
      expect(WebMock).to have_requested(:get, %r{#{Regexp.escape(request_url)}/status}).with { |request|
        request_query(request) == { 'id' => 'abc123' } &&
          valid_signed_headers?(request, user_id:, hmac_key_id:)
      }
    end

    it 'logs scan_status and increments a per-outcome StatsD metric on success' do
      stub_request(:get, %r{#{Regexp.escape(request_url)}/status}).to_return(
        status: 200,
        body: { scan_status: 'failed', error: { error_message: 'boom' } }.to_json,
        headers: { 'Content-Type' => 'application/json' }
      )
      allow(Rails.logger).to receive(:info)

      expect { client.status('abc123', user_id:) }
        .to trigger_statsd_increment('api.cave.idp_client.status.failed')
      expect(Rails.logger).to have_received(:info)
        .with('[Idp::Client] request success', hash_including(scan_status: 'failed'))
    end

    it 'buckets an unrecognized scan_status into a fixed metric name (bounds cardinality)' do
      stub_request(:get, %r{#{Regexp.escape(request_url)}/status}).to_return(
        status: 200,
        body: { scan_status: 'BLARGH' }.to_json,
        headers: { 'Content-Type' => 'application/json' }
      )
      allow(Rails.logger).to receive(:info)

      expect { client.status('abc123', user_id:) }
        .to trigger_statsd_increment('api.cave.idp_client.status.unknown_scan_status')
        .and not_trigger_statsd_increment('api.cave.idp_client.status.BLARGH')
      # the RAW value is still logged even though it is bucketed in the metric name
      expect(Rails.logger).to have_received(:info)
        .with('[Idp::Client] request success', hash_including(scan_status: 'BLARGH'))
    end

    it 'buckets a missing scan_status under no_scan_status' do
      stub_request(:get, %r{#{Regexp.escape(request_url)}/output}).to_return(
        status: 200,
        body: { forms: [] }.to_json,
        headers: { 'Content-Type' => 'application/json' }
      )

      expect { client.output('abc123', type: 'artifact', user_id:) }
        .to trigger_statsd_increment('api.cave.idp_client.output.no_scan_status')
    end

    it 'increments the scan_status bucket for a known status' do
      stub_request(:get, %r{#{Regexp.escape(request_url)}/status}).to_return(
        status: 200,
        body: { scan_status: 'completed' }.to_json,
        headers: { 'Content-Type' => 'application/json' }
      )

      expect { client.status('abc123', user_id:) }
        .to trigger_statsd_increment('api.cave.idp_client.status.completed')
    end

    it 'sends output request and returns parsed payload' do
      stub_request(:get, %r{#{Regexp.escape(request_url)}/output}).to_return(
        status: 200,
        body: { forms: [] }.to_json,
        headers: { 'Content-Type' => 'application/json' }
      )

      response = client.output('abc123', type: 'artifact', user_id:)

      expect(response).to eq('forms' => [])
      expect(WebMock).to have_requested(:get, %r{#{Regexp.escape(request_url)}/output}).with { |request|
        request_query(request) == { 'id' => 'abc123', 'type' => 'artifact' } &&
          valid_signed_headers?(request, user_id:, hmac_key_id:)
      }
    end

    it 'sends download request and returns parsed payload' do
      stub_request(:get, %r{#{Regexp.escape(request_url)}/download}).to_return(
        status: 200,
        body: { data: { foo: 'bar' } }.to_json,
        headers: { 'Content-Type' => 'application/json' }
      )

      response = client.download('abc123', kvpid: 'kvp1', user_id:)

      expect(response).to eq('data' => { 'foo' => 'bar' })
      expect(WebMock).to have_requested(:get, %r{#{Regexp.escape(request_url)}/download}).with { |request|
        request_query(request) == { 'id' => 'abc123', 'kvpid' => 'kvp1' } &&
          valid_signed_headers?(request, user_id:, hmac_key_id:)
      }
    end

    it 'sends update request and returns parsed payload' do
      expected_payload = { FIRST_NAME: 'Ada', LAST_NAME: 'Lovelace' }.to_json
      stub_request(:post, %r{#{Regexp.escape(request_url)}/update}).to_return(
        status: 200,
        body: expected_payload,
        headers: { 'Content-Type' => 'application/json' }
      )

      response = client.update(
        'abc123',
        kvpid: 'kvp1',
        payload: { FIRST_NAME: 'Ada', LAST_NAME: 'Lovelace' },
        user_id:
      )

      expect(response).to eq('FIRST_NAME' => 'Ada', 'LAST_NAME' => 'Lovelace')
      expect(WebMock).to have_requested(:post, %r{#{Regexp.escape(request_url)}/update}).with { |request|
        request_query(request) == { 'id' => 'abc123', 'kvpid' => 'kvp1' } &&
          request.body == expected_payload &&
          request.headers['Content-Type'].to_s.include?('application/json') &&
          valid_signed_headers?(request, user_id:, hmac_key_id:)
      }
    end

    it 'sends corrections request and returns parsed payload' do
      stub_request(:post, %r{#{Regexp.escape(request_url)}/corrections}).to_return(
        status: 200,
        body: { received: true }.to_json,
        headers: { 'Content-Type' => 'application/json' }
      )

      response = client.corrections(
        'abc123',
        kvpid: 'kvp1',
        payload: { corrections: [{ field: 'VETERAN_NAME', ocr_value: 'JON', user_value: 'John' }] },
        user_id:
      )

      expect(response).to eq('received' => true)
      expect(WebMock).to have_requested(:post, %r{#{Regexp.escape(request_url)}/corrections}).with { |request|
        request_query(request) == { 'id' => 'abc123', 'kvpid' => 'kvp1' } &&
          request.body.include?('VETERAN_NAME') &&
          request.headers['Content-Type'].to_s.include?('application/json') &&
          valid_signed_headers?(request, user_id:, hmac_key_id:)
      }
    end

    it 'raises an error when user identity is missing' do
      expect { client.status('abc123', user_id: nil) }.to raise_error(Idp::Error, /user identity is required/)
    end

    it 'raises Idp::Error for timeouts' do
      stub_request(:get, "#{request_url}/status").with(query: { id: 'abc123' }).to_timeout

      expect { client.status('abc123', user_id:) }.to raise_error(Idp::Error) { |error|
        expect(error.transport_failure?).to be(true)
        expect(error.upstream_status).to be_nil
        expect(error.upstream_body).to be_nil
      }
    end

    it 'raises Idp::Error for 5xx responses' do
      stub_request(:get, "#{request_url}/download")
        .with(query: { id: 'abc123', kvpid: 'kvp1' })
        .to_return(status: 500, body: { error: 'upstream error' }.to_json,
                   headers: { 'Content-Type' => 'application/json' })

      expect { client.download('abc123', kvpid: 'kvp1', user_id:) }.to raise_error(Idp::Error, /500/) { |error|
        expect(error.transport_failure?).to be(false)
        expect(error.upstream_status).to eq(500)
        expect(error.upstream_body).to eq('error' => 'upstream error')
        expect(error.failure_category).to eq('upstream_response')
      }
    end

    it 'captures actionable upstream 4xx details for callers' do
      stub_request(:get, "#{request_url}/status")
        .with(query: { id: 'abc123' })
        .to_return(
          status: 404,
          body: {
            errors: [
              {
                code: 'idp_not_found',
                detail: 'Item not found.'
              }
            ]
          }.to_json,
          headers: {
            'Content-Type' => 'application/json',
            'X-Request-Id' => 'upstream-request-id'
          }
        )

      expect { client.status('abc123', user_id:) }.to raise_error(Idp::Error) { |error|
        expect(error.error_type).to eq('idp_not_found')
        expect(error.upstream_status).to eq(404)
        expect(error.upstream_body).to eq(
          'errors' => [
            {
              'code' => 'idp_not_found',
              'detail' => 'Item not found.'
            }
          ]
        )
        expect(error.upstream_headers).to include('x-request-id' => 'upstream-request-id')
        expect(error.failure_category).to eq('upstream_response')
      }
    end

    it 'keeps non-json upstream error bodies without raising parser errors' do
      stub_request(:get, "#{request_url}/status")
        .with(query: { id: 'abc123' })
        .to_return(
          status: 500,
          body: '<html>bad gateway</html>',
          headers: { 'Content-Type' => 'text/html' }
        )

      expect { client.status('abc123', user_id:) }.to raise_error(Idp::Error) { |error|
        expect(error.upstream_status).to eq(500)
        expect(error.upstream_body).to eq('<html>bad gateway</html>')
        expect(error.error_type).to be_nil
      }
    end

    context 'when connect_url is configured' do
      let(:base_url) { 'https://logical-api.execute-api.us-gov-west-1.amazonaws.com/stg/api/v1/doc' }
      let(:connect_url) do
        'https://vpce-connect.execute-api.us-gov-west-1.vpce.amazonaws.com/stg/api/v1/doc'
      end

      before do
        allow(Resolv).to receive(:getaddresses)
          .with('vpce-connect.execute-api.us-gov-west-1.vpce.amazonaws.com')
          .and_return(['10.0.0.10'])
      end

      it 'keeps requests on the logical base_url while resolving connect_url for transport' do
        stub_request(:post, "#{request_url}/intake")
          .with(body: { pdf_b64: 'ZmlsZQ==' }.to_json)
          .to_return(status: 200, body: { id: 'abc123' }.to_json, headers: { 'Content-Type' => 'application/json' })

        client.intake(file_name: 'test.pdf', pdf_base64: 'ZmlsZQ==', user_id:)

        expect(WebMock).to have_requested(:post, "#{request_url}/intake")
        expect(client.send(:connect_ipaddr)).to eq('10.0.0.10')
      end
    end
  end
end
