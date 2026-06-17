# frozen_string_literal: true

require 'rails_helper'

describe V2::Lorota::Client do
  subject { described_class.build(check_in:) }

  let(:check_in) do
    CheckIn::V2::Session.build(data: { uuid: 'd602d9eb-9a31-484f-9637-13ab0b507e0d', dob: '1970-02-20',
                                       last_name: 'last' })
  end

  describe 'attributes' do
    it 'responds to claims_token' do
      expect(subject.respond_to?(:claims_token)).to be(true)
    end

    it 'responds to check_in' do
      expect(subject.respond_to?(:check_in)).to be(true)
    end

    it 'responds to settings' do
      expect(subject.respond_to?(:settings)).to be(true)
    end
  end

  describe '.build' do
    it 'returns an instance of Client' do
      expect(subject).to be_an_instance_of(V2::Lorota::Client)
    end
  end

  describe '#token' do
    let(:token) do
      'eyJraWQiOiJRMFZKbEt0TU9rYUxXTEtxdXhsTllHQzFRLWMtblQzYjRWVlJLaXB4TThzIiwiYWxnIj'
    end
    let(:faraday_response) { double('Faraday::Response', body: { 'token' => token }.to_json) }

    before do
      allow_any_instance_of(Faraday::Connection).to receive(:post).with(anything).and_return(faraday_response)
    end

    it 'returns the token' do
      expect(subject.token).to eq(faraday_response)
    end

    it 'yields to block' do
      expect_any_instance_of(Faraday::Connection).to receive(:post).with(anything).and_yield(Faraday::Request.new)

      subject.token
    end

    context 'when called dob in session model' do
      let(:auth_param_with_dob) do
        { lastName: 'last', dob: '1970-02-20' }
      end

      before do
        allow(Flipper).to receive(:enabled?).with('check_in_experience_mock_enabled').and_return(false)
      end

      it 'uses dob in auth_params to call lorota endpoint' do
        expect_any_instance_of(Faraday::Connection).to receive(:post).with(anything) do |&block|
          result = block.call(Faraday::Request.new)
          expect(result).to eq(auth_param_with_dob.to_json)
        end

        subject.token
      end
    end
  end

  describe '#data' do
    let(:token) do
      'eyJraWQiOiJRMFZKbEt0TU9rYUxXTEtxdXhsTllHQzFRLWMtblQzYjRWVlJLaXB4TThzIiwiYWxnIj'
    end
    let(:faraday_response) { double('Faraday::Response') }

    before do
      allow_any_instance_of(Faraday::Connection).to receive(:get).with(anything).and_return(faraday_response)
    end

    it 'returns a valid response' do
      expect(subject.data(token:)).to eq(faraday_response)
    end

    it 'yields to block' do
      expect_any_instance_of(Faraday::Connection).to receive(:get).with(anything).and_yield(Faraday::Request.new)

      subject.data(token:)
    end
  end

  describe 'LoROTA configuration' do
    let(:token) { 'test_token' }
    let(:faraday_response) { double('Faraday::Response', body: { 'token' => token }.to_json) }

    before do
      allow_any_instance_of(Faraday::Connection).to receive(:post).with(anything).and_return(faraday_response)
      allow_any_instance_of(Faraday::Connection).to receive(:get).with(anything).and_return(faraday_response)
      allow(Flipper).to receive(:enabled?).with('check_in_experience_mock_enabled').and_return(false)
    end

    it 'uses the configured LoROTA settings' do
      expect(subject.send(:url)).to eq(Settings.check_in.lorota_v2.url)
      expect(subject.send(:base_path)).to eq(Settings.check_in.lorota_v2.base_path)
      expect(subject.send(:api_id)).to eq(Settings.check_in.lorota_v2.api_id)
      expect(subject.send(:api_key)).to eq(Settings.check_in.lorota_v2.api_key)
    end

    it 'makes the token request to the configured endpoint' do
      expect_any_instance_of(Faraday::Connection).to receive(:post).with('/dev/token')
      subject.token
    end

    it 'makes the data request to the configured endpoint' do
      expect_any_instance_of(Faraday::Connection).to receive(:get)
        .with("/dev/data/#{check_in.uuid}")
      subject.data(token:)
    end

    it 'sets the api key and api id request headers' do
      expect_any_instance_of(Faraday::Connection).to receive(:post).with(anything) do |&block|
        request = Faraday::Request.new
        block.call(request)
        expect(request.headers['x-api-key']).to eq(Settings.check_in.lorota_v2.api_key)
        expect(request.headers['x-apigw-api-id']).to eq(Settings.check_in.lorota_v2.api_id)
      end
      subject.token
    end
  end

  describe 'URL composition' do
    let(:token) { 'test_token' }
    let(:faraday_response) { double('Faraday::Response', body: { 'token' => token }.to_json) }

    before do
      allow_any_instance_of(Faraday::Connection).to receive(:post).with(anything).and_return(faraday_response)
      allow_any_instance_of(Faraday::Connection).to receive(:get).with(anything).and_return(faraday_response)
      allow(Flipper).to receive(:enabled?).with('check_in_experience_mock_enabled').and_return(false)
    end

    context 'when url contains only the host and base_path carries the stage' do
      before do
        allow(Settings.check_in.lorota_v2).to receive_messages(
          url: 'https://example.execute-api.us-gov-west-1.amazonaws.com',
          base_path: 'dev'
        )
      end

      it 'builds the request path from base_path' do
        expect_any_instance_of(Faraday::Connection).to receive(:post).with('/dev/token')
        subject.token
      end

      it 'builds the data request path from base_path' do
        expect_any_instance_of(Faraday::Connection).to receive(:get).with("/dev/data/#{check_in.uuid}")
        subject.data(token:)
      end
    end

    context 'when url already contains the stage path' do
      before do
        allow(Settings.check_in.lorota_v2).to receive_messages(
          url: 'https://example.execute-api.us-gov-west-1.amazonaws.com/dev',
          base_path: '/dev'
        )
      end

      it 'uses the url path and ignores base_path to avoid duplication' do
        expect_any_instance_of(Faraday::Connection).to receive(:post).with('/dev/token')
        subject.token
      end

      it 'uses the url path for the data request' do
        expect_any_instance_of(Faraday::Connection).to receive(:get).with("/dev/data/#{check_in.uuid}")
        subject.data(token:)
      end
    end

    context 'when base_path has a leading slash and url has no path' do
      before do
        allow(Settings.check_in.lorota_v2).to receive_messages(
          url: 'https://example.execute-api.us-gov-west-1.amazonaws.com',
          base_path: '/dev/'
        )
      end

      it 'strips the slashes from base_path' do
        expect_any_instance_of(Faraday::Connection).to receive(:post).with('/dev/token')
        subject.token
      end
    end

    context 'when url has a trailing slash on its path' do
      before do
        allow(Settings.check_in.lorota_v2).to receive_messages(
          url: 'https://example.execute-api.us-gov-west-1.amazonaws.com/dev/',
          base_path: ''
        )
      end

      it 'strips the trailing slash from the url path' do
        expect_any_instance_of(Faraday::Connection).to receive(:post).with('/dev/token')
        subject.token
      end
    end
  end
end
