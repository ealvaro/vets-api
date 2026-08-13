# frozen_string_literal: true

require 'rails_helper'
require 'pager_duty/cache_global_downtime'

RSpec.describe PagerDuty::CacheGlobalDowntime, type: %i[job aws_helpers] do
  let(:subject) { described_class.new }

  let(:client_stub) { instance_double(PagerDuty::MaintenanceClient) }
  let(:mw_hash) { build(:maintenance_hash) }

  before do
    allow(Settings.maintenance).to receive(:services).and_return({ global: 'ABCDEF' })
    allow(Settings.maintenance.aws).to receive_messages(access_key_id: 'key', secret_access_key: 'secret',
                                                        bucket: 'bucket', region: 'region')
    allow(PagerDuty::MaintenanceClient).to receive(:new) { client_stub }
  end

  describe '#perform' do
    context 'with success response from client' do
      let(:filename) { 'tmp/maintenance_windows.json' }
      let(:options) { { 'service_ids' => %w[ABCDEF] } }

      before { stub_maintenance_windows_s3(filename) }

      after { File.delete(filename) }

      it 'uploads an empty list of global downtimes' do
        allow(client_stub).to receive(:get_all).with(options).and_return([])
        subject.perform
        expect(File.read(filename)).to eq('[]')
      end

      it 'uploads a populated list of global downtimes' do
        allow(client_stub).to receive(:get_all).with(options).and_return([mw_hash])
        subject.perform
        expect(File.read(filename)).to eq("[#{mw_hash.to_json}]")
      end
    end

    context 'with no global service configured' do
      before { allow(Settings.maintenance).to receive(:services).and_return({ facility_locator_app: 'PT3IBV8' }) }

      it 'does not query PagerDuty with an empty service id' do
        expect(client_stub).not_to receive(:get_all)

        subject.perform
      end
    end

    context 'with error response from client' do
      it 'bails on backend error' do
        expect(client_stub).to receive(:get_all).and_raise(Common::Exceptions::BackendServiceException)
        expect(Rails.logger).to receive(:error)

        subject.perform
      end

      it 'bails on client error' do
        expect(client_stub).to receive(:get_all).and_raise(Common::Client::Errors::ClientError)
        expect(Rails.logger).to receive(:error)

        subject.perform
      end
    end
  end
end
