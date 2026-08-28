# frozen_string_literal: true

require 'rails_helper'
require 'search_kendra/configuration'

describe SearchKendra::Configuration do
  subject(:config) { described_class.instance }

  let(:client) { instance_double(Aws::Kendra::Client) }

  before do
    config.remove_instance_variable(:@client) if config.instance_variable_defined?(:@client)

    allow(Settings.search_kendra).to receive_messages(
      index_id: 'test-index',
      region: 'us-gov-west-1'
    )

    allow(Aws::Kendra::Client).to receive(:new)
      .with(region: 'us-gov-west-1')
      .and_return(client)
  end

  describe '#service_name' do
    it 'returns the service name' do
      expect(config.service_name).to eq('SearchKendra/Results')
    end
  end

  describe '#index_id' do
    it 'returns the configured index id' do
      expect(config.index_id).to eq('test-index')
    end
  end

  describe '#region' do
    it 'returns the configured region' do
      expect(config.region).to eq('us-gov-west-1')
    end
  end

  describe '#client' do
    it 'returns an Aws::Kendra::Client' do
      expect(config.client).to be(client)
    end

    it 'memoizes the client' do
      2.times { config.client }

      expect(Aws::Kendra::Client).to have_received(:new).once
    end

    it 'constructs the client with the configured region' do
      config.client

      expect(Aws::Kendra::Client)
        .to have_received(:new)
        .with(region: 'us-gov-west-1')
    end
  end

  describe '#base_path' do
    it 'returns a Kendra URI' do
      expect(subject.base_path).to eq("kendra://#{Settings.search_kendra.region}")
    end
  end

  describe '#breakers_matcher' do
    it 'never matches requests' do
      expect(subject.breakers_matcher.call).to be(false)
    end
  end

  describe '#breakers_exception_handler' do
    it 'handles Kendra service errors' do
      error = Aws::Kendra::Errors::ServiceError.new(nil, 'Kendra error')

      expect(subject.breakers_exception_handler.call(error)).to be(true)
    end

    it 'does not handle unrelated errors' do
      expect(subject.breakers_exception_handler.call(StandardError.new)).to be(false)
    end
  end

  describe '#with_breakers' do
    it 'records a Kendra service error' do
      error = Aws::Kendra::Errors::ServiceError.new(nil, 'Kendra error')

      expect do
        subject.with_breakers { raise error }
      end.to raise_error(Aws::Kendra::Errors::ServiceError)

      expect(subject.breakers_service.latest_outage).to be_present
    end
  end

  describe '#outage_blocks_request?' do
    let(:service) { instance_double(Breakers::Service) }
    let(:outage) { instance_double(Breakers::Outage) }

    it 'blocks an active outage that is not ready for retest' do
      allow(outage).to receive_messages(
        ended?: false,
        forced?: false,
        ready_for_retest?: false
      )
      allow(service).to receive(:seconds_before_retry).and_return(60)

      expect(subject.send(:outage_blocks_request?, outage, service)).to be(true)
    end

    it 'allows an ended outage' do
      allow(outage).to receive(:ended?).and_return(true)

      expect(subject.send(:outage_blocks_request?, outage, service)).to be(false)
    end

    it 'allows a forced outage' do
      allow(outage).to receive_messages(ended?: false, forced?: true)

      expect(subject.send(:outage_blocks_request?, outage, service)).to be(false)
    end

    it 'allows an outage ready for retest' do
      allow(outage).to receive_messages(
        ended?: false,
        forced?: false,
        ready_for_retest?: true
      )
      allow(service).to receive(:seconds_before_retry).and_return(60)

      expect(subject.send(:outage_blocks_request?, outage, service)).to be(false)
    end
  end

  describe '#notify_plugins' do
    let(:service) { instance_double(Breakers::Service) }
    let(:plugin) { double('plugin') }

    before do
      allow(Breakers.client).to receive(:plugins).and_return([plugin])
    end

    it 'notifies plugins for skipped requests' do
      allow(plugin).to receive(:on_skipped_request)

      subject.send(:notify_plugins, :on_skipped_request, service)

      expect(plugin).to have_received(:on_skipped_request).with(service)
    end

    it 'notifies plugins for successful requests' do
      allow(plugin).to receive(:on_success)

      subject.send(:notify_plugins, :on_success, service)

      expect(plugin).to have_received(:on_success).with(service, nil, nil)
    end

    it 'notifies plugins for failed requests' do
      allow(plugin).to receive(:on_error)

      subject.send(:notify_plugins, :on_error, service)

      expect(plugin).to have_received(:on_error).with(service, nil, nil)
    end

    it 'skips plugins that do not support the hook' do
      allow(plugin).to receive(:on_success)

      other_plugin = double('other_plugin')

      allow(Breakers.client).to receive(:plugins).and_return([other_plugin])

      subject.send(:notify_plugins, :on_success, service)

      expect(plugin).not_to have_received(:on_success)
    end
  end
end
