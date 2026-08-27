# frozen_string_literal: true

require 'rails_helper'
require 'rack_attack/throttle_logger'

RSpec.describe RackAttack::ThrottleLogger do
  subject(:log!) { described_class.log(request) }

  let(:request) { build_request }

  # Captures the payload handed to Rails.logger.info, so specs can assert on the
  # emitted fields rather than on the masking helpers in isolation.
  let(:payload) do
    captured = nil
    allow(StatsD).to receive(:increment)
    allow(Rails.logger).to receive(:info) { |_msg, hash| captured = hash }
    log!
    captured
  end

  def build_request(remote_addr: '10.1.2.3',
                    x_real_ip: '203.0.113.5',
                    x_forwarded_for: '203.0.113.5, 10.1.2.3',
                    discriminator: '203.0.113.5')
    env = Rack::MockRequest.env_for(
      '/facilities_api/v2/va',
      'REMOTE_ADDR' => remote_addr,
      'HTTP_X_REAL_IP' => x_real_ip,
      'HTTP_X_FORWARDED_FOR' => x_forwarded_for
    )
    # Mirror the env the rack-attack gem sets when a throttle is exceeded.
    env['rack.attack.matched'] = 'facilities_api/v2/va/ip'
    env['rack.attack.match_type'] = :throttle
    env['rack.attack.match_discriminator'] = discriminator
    env['rack.attack.match_data'] = { discriminator:, count: 31, limit: 30, period: 60 }
    Rack::Attack::Request.new(env)
  end

  before { allow(Flipper).to receive(:enabled?).with(described_class::FLAG).and_return(true) }

  describe '.log' do
    it 'logs the matched rule and request metadata' do
      expect(payload).to include(
        rule: 'facilities_api/v2/va/ip',
        path: '/facilities_api/v2/va',
        request_method: 'GET',
        count: 31,
        limit: 30,
        period: 60,
        safe_keys: described_class::SAFE_KEYS
      )
    end

    it 'increments a StatsD counter tagged by rule' do
      allow(Rails.logger).to receive(:info)
      expect(StatsD).to receive(:increment)
        .with('rack_attack.throttled', tags: ['rule:facilities_api/v2/va/ip'])
      log!
    end

    # The whole point of the change: the log must carry no recoverable address.
    it 'never emits a raw IP anywhere in the payload' do
      serialized = payload.to_s

      expect(serialized).not_to include('203.0.113.5')
      expect(serialized).not_to include('10.1.2.3')
    end

    it 'replaces every IP field with a prefixed token' do
      expect(payload).to include(
        discriminator: a_string_matching(/\Aip_\h{16}\z/),
        discriminator_net: a_string_matching(/\Anet_\h{16}\z/),
        computed_remote_ip: a_string_matching(/\Aip_\h{16}\z/),
        remote_addr: a_string_matching(/\Aip_\h{16}\z/),
        x_real_ip: a_string_matching(/\Aip_\h{16}\z/),
        x_forwarded_for: a_string_matching(/\Aip_\h{16}, ip_\h{16}\z/),
        x_forwarded_for_client: a_string_matching(/\Aip_\h{16}\z/)
      )
    end

    it 'omits fields whose headers are absent rather than tokenizing nil' do
      env = Rack::MockRequest.env_for('/facilities_api/v2/va', 'REMOTE_ADDR' => '10.1.2.3')
      env['rack.attack.matched'] = 'facilities_api/v2/va/ip'
      env['rack.attack.match_discriminator'] = '10.1.2.3'
      captured = nil
      allow(StatsD).to receive(:increment)
      allow(Rails.logger).to receive(:info) { |_msg, hash| captured = hash }
      described_class.log(Rack::Attack::Request.new(env))

      expect(captured[:x_real_ip]).to be_nil
      expect(captured[:x_forwarded_for]).to be_nil
      expect(captured[:x_forwarded_for_client]).to be_nil
      expect(captured[:x_forwarded_for_hops]).to be_nil
      expect(captured[:discriminator_hop]).to be_nil
    end
  end

  # The hops ahead of the throttled address are what separate "one noisy client"
  # from "we merged a crowd into one bucket", so they have to survive masking.
  describe 'the forwarding chain' do
    it 'keeps every hop, in client-first order' do
      request = build_request(x_forwarded_for: '198.51.100.7, 203.0.113.5, 10.1.2.3')

      expect(described_class.diagnostics(request)).to include(
        x_forwarded_for: [described_class.mask_ip('198.51.100.7'),
                          described_class.mask_ip('203.0.113.5'),
                          described_class.mask_ip('10.1.2.3')].join(', '),
        x_forwarded_for_client: described_class.mask_ip('198.51.100.7'),
        x_forwarded_for_hops: 3
      )
    end

    it 'reports where in the chain the throttle bucket was drawn from' do
      request = build_request(x_forwarded_for: '198.51.100.7, 203.0.113.5, 10.1.2.3',
                              discriminator: '203.0.113.5')

      expect(described_class.diagnostics(request)[:discriminator_hop]).to eq(1)
    end

    it 'reports hop 0 when we bucket on the client-nearest hop' do
      request = build_request(x_forwarded_for: '198.51.100.7, 10.1.2.3', discriminator: '198.51.100.7')

      expect(described_class.diagnostics(request)[:discriminator_hop]).to eq(0)
    end

    it 'reports a nil hop when the discriminator is not in the chain' do
      request = build_request(x_forwarded_for: '198.51.100.7, 10.1.2.3', discriminator: '192.0.2.99')

      expect(described_class.diagnostics(request)[:discriminator_hop]).to be_nil
    end

    # The collapse signature itself: one bucket, many distinct clients behind it.
    it 'shows a shared discriminator behind differing client hops' do
      shared = described_class.mask_ip('203.0.113.5')
      first = described_class.diagnostics(build_request(x_forwarded_for: '198.51.100.7, 203.0.113.5'))
      second = described_class.diagnostics(build_request(x_forwarded_for: '198.51.100.8, 203.0.113.5'))

      expect(first[:discriminator]).to eq(shared)
      expect(second[:discriminator]).to eq(shared)
      expect(first[:x_forwarded_for_client]).not_to eq(second[:x_forwarded_for_client])
    end
  end

  # Tokens are only useful if equality survives the masking -- that is what makes
  # "many clients, one bucket" legible in a log stream.
  describe 'token stability' do
    it 'gives the same address the same token every time' do
      first = described_class.mask_ip('203.0.113.5')

      expect(described_class.mask_ip('203.0.113.5')).to eq(first)
    end

    it 'gives different addresses different tokens' do
      expect(described_class.mask_ip('203.0.113.5')).not_to eq(described_class.mask_ip('203.0.113.6'))
    end

    it 'tokenizes equivalent spellings of one IPv6 address identically' do
      canonical = described_class.mask_ip('2001:db8::1')

      expect(described_class.mask_ip('2001:DB8::1')).to eq(canonical)
      expect(described_class.mask_ip('2001:db8:0:0:0:0:0:1')).to eq(canonical)
    end

    it 'derives the same discriminator token in the log as a direct mask' do
      expect(payload[:discriminator]).to eq(described_class.mask_ip('203.0.113.5'))
    end
  end

  # The net_ token is what distinguishes "one host hammering" from "a subnet
  # spraying" now that the address itself is no longer visible.
  describe 'network tokens' do
    it 'gives hosts in the same /24 the same net token but different ip tokens' do
      expect(described_class.mask_network('203.0.113.5')).to eq(described_class.mask_network('203.0.113.200'))
      expect(described_class.mask_ip('203.0.113.5')).not_to eq(described_class.mask_ip('203.0.113.200'))
    end

    it 'gives hosts in different /24s different net tokens' do
      expect(described_class.mask_network('203.0.113.5')).not_to eq(described_class.mask_network('203.0.114.5'))
    end

    it 'groups IPv6 addresses by /48' do
      expect(described_class.mask_network('2001:db8:1::1')).to eq(described_class.mask_network('2001:db8:1:ffff::9'))
      expect(described_class.mask_network('2001:db8:1::1')).not_to eq(described_class.mask_network('2001:db8:2::1'))
    end

    it 'does not collide the ip and net namespaces for the same input' do
      expect(described_class.mask_ip('203.0.113.0').sub(/\Aip_/, ''))
        .not_to eq(described_class.mask_network('203.0.113.0').sub(/\Anet_/, ''))
    end
  end

  describe 'the HMAC key' do
    it 'uses the configured secret when one is set' do
      with_settings(Settings.rack_attack.throttle_log, hash_secret: 'secret-one') do
        @first = described_class.mask_ip('203.0.113.5')
        @first_key_id = described_class.hash_key_id
      end
      with_settings(Settings.rack_attack.throttle_log, hash_secret: 'secret-two') do
        expect(described_class.mask_ip('203.0.113.5')).not_to eq(@first)
        expect(described_class.hash_key_id).not_to eq(@first_key_id)
      end
    end

    it 'falls back to secret_key_base when the setting is blank' do
      with_settings(Settings.rack_attack.throttle_log, hash_secret: nil) do
        expect(described_class.hash_key).to eq(Rails.application.secret_key_base)
        expect(described_class.mask_ip('203.0.113.5')).to match(/\Aip_\h{16}\z/)
      end
    end

    it 'logs a key fingerprint so a rotation is not mistaken for new clients' do
      expect(payload[:hash_key_id]).to match(/\A\h{8}\z/)
    end

    it 'does not leak the key through the fingerprint' do
      with_settings(Settings.rack_attack.throttle_log, hash_secret: 'secret-one') do
        expect(described_class.hash_key_id).not_to include('secret-one')
      end
    end
  end

  describe 'non-IP values' do
    it 'does not log when the discriminator is a SHA256 email digest' do
      allow(Rails.logger).to receive(:info)
      allow(StatsD).to receive(:increment)
      described_class.log(build_request(discriminator: Digest::SHA256.hexdigest('veteran@example.com')))

      expect(Rails.logger).not_to have_received(:info)
      expect(StatsD).not_to have_received(:increment)
    end

    it 'does not log when the discriminator is nil' do
      allow(Rails.logger).to receive(:info)
      allow(StatsD).to receive(:increment)
      described_class.log(build_request(discriminator: nil))

      expect(Rails.logger).not_to have_received(:info)
      expect(StatsD).not_to have_received(:increment)
    end

    # Attacker-controlled header values must never be echoed into the log verbatim.
    it 'marks unparseable header values instead of passing them through' do
      captured = nil
      allow(StatsD).to receive(:increment)
      allow(Rails.logger).to receive(:info) { |_msg, hash| captured = hash }
      described_class.log(build_request(x_real_ip: 'not-an-ip', x_forwarded_for: '203.0.113.5, <script>'))

      expect(captured[:x_real_ip]).to eq(described_class::INVALID_IP)
      expect(captured[:x_forwarded_for]).to eq("#{described_class.mask_ip('203.0.113.5')}, " \
                                               "#{described_class::INVALID_IP}")
    end
  end

  # `ip_like?` uses Resolv's address regex, which is looser than IPAddr for
  # compressed IPv6: `1:2:3:4:5:6:7:8::9` carries more than eight groups, so the
  # regex accepts it and `IPAddr.new` rejects it. A caller can put that in
  # X-Forwarded-For, so it is real input, not a hypothetical.
  describe 'values that pass the IP regex but not IPAddr' do
    let(:overlong_ipv6) { '1:2:3:4:5:6:7:8::9' }

    it 'marks the network as invalid rather than raising' do
      expect(described_class.mask_network(overlong_ipv6)).to eq(described_class::INVALID_IP)
    end

    it 'still tokenizes the address without echoing it' do
      masked = described_class.mask_ip(overlong_ipv6)

      expect(masked).to match(/\Aip_\h{16}\z/)
      expect(masked).not_to include(overlong_ipv6)
    end

    it 'keeps the token stable when canonicalization falls back to the raw value' do
      first = described_class.mask_ip(overlong_ipv6)

      expect(described_class.mask_ip(overlong_ipv6)).to eq(first)
    end

    it 'logs the throttle with an invalid network alongside the tokenized address' do
      captured = nil
      allow(StatsD).to receive(:increment)
      allow(Rails.logger).to receive(:info) { |_msg, hash| captured = hash }
      described_class.log(build_request(discriminator: overlong_ipv6, x_forwarded_for: overlong_ipv6))

      expect(captured[:discriminator]).to match(/\Aip_\h{16}\z/)
      expect(captured[:discriminator_net]).to eq(described_class::INVALID_IP)
      expect(captured.to_s).not_to include(overlong_ipv6)
    end
  end

  # `Rack::Attack::Request#remote_ip` compares REMOTE_ADDR against the configured
  # trusted proxies with `case/when`, and `IPAddr#===` raises on a REMOTE_ADDR that
  # isn't an address. Diagnostics must not turn that into a failed request.
  describe 'when the computed remote_ip raises' do
    let(:request) { build_request(remote_addr: 'not-an-ip') }

    before do
      allow(Rails.application.config.action_dispatch)
        .to receive(:trusted_proxies).and_return([IPAddr.new('10.0.0.0/8')])
    end

    it 'confirms the request object really raises on remote_ip' do
      expect { request.remote_ip }.to raise_error(IPAddr::Error)
    end

    it 'omits computed_remote_ip and still logs the rest' do
      expect(payload).to include(
        computed_remote_ip: nil,
        remote_addr: described_class::INVALID_IP,
        discriminator: described_class.mask_ip('203.0.113.5')
      )
    end
  end

  describe 'guard rails' do
    it 'does nothing when the flag is disabled' do
      allow(Flipper).to receive(:enabled?).with(described_class::FLAG).and_return(false)
      allow(Rails.logger).to receive(:info)
      allow(StatsD).to receive(:increment)
      log!

      expect(Rails.logger).not_to have_received(:info)
      expect(StatsD).not_to have_received(:increment)
    end

    it 'swallows errors so the request path is unaffected' do
      allow(Rails.logger).to receive(:info).and_raise(StandardError, 'boom')
      expect(Rails.logger).to receive(:error)
        .with('RackAttack::ThrottleLogger failed', hash_including(exception: an_instance_of(StandardError)))
      expect { log! }.not_to raise_error
    end
  end
end
