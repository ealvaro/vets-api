# frozen_string_literal: true

require 'rails_helper'

RSpec.describe SignIn::LocationParser do
  let(:fixture_path) { 'spec/fixtures/sign_in/GeoLite2-City-Test.mmdb' }
  let(:fixture_city) { 'Test City' }
  let(:fixture_region) { 'Test Region' }

  before do
    allow(IdentitySettings.sign_in.geolite2).to receive(:path).and_return(fixture_path)
    described_class.reader_instance = nil
  end

  after { described_class.reader_instance = nil }

  describe '.parse' do
    subject { described_class.parse(ip) }

    context 'with a public IP the fixture resolves' do
      let(:ip) { '8.8.8.8' }

      it 'returns City, Region from the real reader' do
        expect(subject).to eq("#{fixture_city}, #{fixture_region}")
      end
    end

    context 'when the record has a city but no region' do
      let(:ip) { '8.8.8.8' }
      let(:record) do
        instance_double(
          MaxMind::GeoIP2::Model::City,
          city: instance_double(MaxMind::GeoIP2::Record::City, name: 'Lonelyville'),
          most_specific_subdivision: instance_double(MaxMind::GeoIP2::Record::Subdivision, name: nil)
        )
      end

      before { allow(described_class.reader).to receive(:city).with(ip).and_return(record) }

      it 'returns just the city' do
        expect(subject).to eq('Lonelyville')
      end
    end

    context 'when the record has a region but no city' do
      let(:ip) { '8.8.8.8' }
      let(:record) do
        instance_double(
          MaxMind::GeoIP2::Model::City,
          city: instance_double(MaxMind::GeoIP2::Record::City, name: nil),
          most_specific_subdivision: instance_double(MaxMind::GeoIP2::Record::Subdivision, name: 'Nowhere Province')
        )
      end

      before { allow(described_class.reader).to receive(:city).with(ip).and_return(record) }

      it 'returns just the region' do
        expect(subject).to eq('Nowhere Province')
      end
    end

    context 'when the record has neither city nor region' do
      let(:ip) { '8.8.8.8' }
      let(:record) do
        instance_double(
          MaxMind::GeoIP2::Model::City,
          city: instance_double(MaxMind::GeoIP2::Record::City, name: nil),
          most_specific_subdivision: instance_double(MaxMind::GeoIP2::Record::Subdivision, name: nil)
        )
      end

      before { allow(described_class.reader).to receive(:city).with(ip).and_return(record) }

      it 'returns nil' do
        expect(subject).to be_nil
      end
    end

    context 'with a loopback address' do
      let(:ip) { '127.0.0.1' }

      it 'returns nil' do
        expect(subject).to be_nil
      end
    end

    context 'with a private LAN address' do
      let(:ip) { '192.168.1.10' }

      it 'returns nil' do
        expect(subject).to be_nil
      end
    end

    context 'with an IPv6 loopback' do
      let(:ip) { '::1' }

      it 'returns nil' do
        expect(subject).to be_nil
      end
    end

    context 'with a link-local address' do
      let(:ip) { '169.254.1.1' }

      it 'returns nil' do
        expect(subject).to be_nil
      end
    end

    context 'when the ip is nil' do
      let(:ip) { nil }

      it 'returns nil' do
        expect(subject).to be_nil
      end
    end

    context 'when the ip is malformed' do
      let(:ip) { 'not-an-ip' }

      it 'returns nil' do
        expect(subject).to be_nil
      end
    end

    context 'when the database file is absent' do
      let(:ip) { '8.8.8.8' }

      before do
        allow(IdentitySettings.sign_in.geolite2).to receive(:path).and_return('nonexistent/path.mmdb')
        described_class.reader_instance = nil
      end

      it 'returns nil without raising' do
        expect(subject).to be_nil
      end
    end
  end
end
