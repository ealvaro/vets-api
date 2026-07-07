# frozen_string_literal: true

require 'rails_helper'
require 'mhv/aal/configuration'

RSpec.describe AAL::Configuration do
  # Whether a given configuration's Faraday stack includes the Betamocks middleware.
  def betamocks?(config)
    config.connection.builder.handlers.map(&:name).include?('Betamocks::Middleware')
  end

  describe '#mock?' do
    it 'is disabled on the namespace-agnostic base configuration' do
      expect(AAL::Configuration.instance.mock?).to be(false)
    end

    it 'reads the aal namespace for AALConfiguration' do
      allow(Settings.mhv.aal).to receive(:mock).and_return('aal-sentinel')
      expect(AAL::AALConfiguration.instance.mock?).to eq('aal-sentinel')
    end

    it 'reads the rx namespace for RXConfiguration' do
      allow(Settings.mhv.rx).to receive(:mock).and_return('rx-sentinel')
      expect(AAL::RXConfiguration.instance.mock?).to eq('rx-sentinel')
    end

    it 'reads the sm namespace for SMConfiguration' do
      allow(Settings.mhv.sm).to receive(:mock).and_return('sm-sentinel')
      expect(AAL::SMConfiguration.instance.mock?).to eq('sm-sentinel')
    end

    it 'reads the medical_records namespace for MRConfiguration' do
      # medical_records has no `mock` key (Config::Options resolves it via
      # method_missing), so stub the parent to supply a stand-in that responds to it.
      allow(Settings.mhv).to receive(:medical_records).and_return(
        double('medical_records', mock: 'mr-sentinel')
      )
      expect(AAL::MRConfiguration.instance.mock?).to eq('mr-sentinel')
    end
  end

  describe '#connection Betamocks wiring' do
    context 'when mhv.aal.mock is enabled' do
      before { allow(Settings.mhv.aal).to receive(:mock).and_return(true) }

      it 'enables Betamocks for the AAL configuration' do
        expect(betamocks?(AAL::AALConfiguration.instance)).to be(true)
      end
    end

    context 'when mhv.aal.mock is disabled' do
      before { allow(Settings.mhv.aal).to receive(:mock).and_return(false) }

      it 'does not enable Betamocks for the AAL configuration' do
        expect(betamocks?(AAL::AALConfiguration.instance)).to be(false)
      end
    end

    describe 'isolation from mhv.aal.mock' do
      before { allow(Settings.mhv.aal).to receive(:mock).and_return(true) }

      it 'does not enable Betamocks for the RX configuration' do
        allow(Settings.mhv.rx).to receive(:mock).and_return(false)
        expect(betamocks?(AAL::RXConfiguration.instance)).to be(false)
      end

      it 'does not enable Betamocks for the SM configuration' do
        allow(Settings.mhv.sm).to receive(:mock).and_return(false)
        expect(betamocks?(AAL::SMConfiguration.instance)).to be(false)
      end

      it 'does not enable Betamocks for the MR configuration' do
        # medical_records has no `mock` setting, so it resolves to disabled.
        expect(betamocks?(AAL::MRConfiguration.instance)).to be(false)
      end
    end

    describe 'each product namespace drives its own connection' do
      before { allow(Settings.mhv.aal).to receive(:mock).and_return(false) }

      it 'enables Betamocks for RX when mhv.rx.mock is true' do
        allow(Settings.mhv.rx).to receive(:mock).and_return(true)
        expect(betamocks?(AAL::RXConfiguration.instance)).to be(true)
      end

      it 'enables Betamocks for SM when mhv.sm.mock is true' do
        allow(Settings.mhv.sm).to receive(:mock).and_return(true)
        expect(betamocks?(AAL::SMConfiguration.instance)).to be(true)
      end
    end
  end
end
