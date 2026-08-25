# frozen_string_literal: true

require 'rails_helper'
require 'benefits_intake_service/configuration'

RSpec.describe BenefitsIntakeService::Configuration do
  subject(:config) { described_class.instance }

  describe '#api_key' do
    context 'when benefits_intake_service.api_key is set' do
      before { allow(Settings.benefits_intake_service).to receive(:api_key).and_return('bis-key') }

      it 'returns the primary key' do
        expect(config.api_key).to eq('bis-key')
      end
    end

    context 'when benefits_intake_service.api_key is blank' do
      before do
        allow(Settings.benefits_intake_service).to receive(:api_key).and_return(nil)
        allow(Settings.form526_backup).to receive(:api_key).and_return('backup-key')
      end

      it 'falls back to form526_backup.api_key' do
        expect(config.api_key).to eq('backup-key')
      end
    end
  end

  describe '#base_path' do
    context 'when benefits_intake_service.url is set' do
      before { allow(Settings.benefits_intake_service).to receive(:url).and_return('https://primary.va.gov') }

      it 'returns the primary url' do
        expect(config.base_path).to eq('https://primary.va.gov')
      end
    end

    context 'when benefits_intake_service.url is blank' do
      before do
        allow(Settings.benefits_intake_service).to receive(:url).and_return(nil)
        allow(Settings.form526_backup).to receive(:url).and_return('https://backup.va.gov')
      end

      it 'falls back to form526_backup.url' do
        expect(config.base_path).to eq('https://backup.va.gov')
      end
    end
  end

  describe '.base_request_headers' do
    before { allow(Settings.benefits_intake_service).to receive(:api_key).and_return('test-key') }

    it 'includes the api_key header' do
      expect(described_class.base_request_headers['apikey']).to eq('test-key')
    end
  end

  describe '#service_name' do
    it { expect(config.service_name).to eq('BenefitsIntakeService') }
  end

  describe '#breakers_error_threshold' do
    it { expect(config.breakers_error_threshold).to eq(80) }
  end
end
