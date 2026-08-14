# frozen_string_literal: true

require 'rails_helper'
require 'idp'
require 'idp/mock_client'

RSpec.describe Idp do
  describe Idp::Error do
    it 'raises when unexpected context keys are provided' do
      expect { described_class.new('boom', upsteam_status: 500) }
        .to raise_error(ArgumentError)
    end

    it 'accepts the supported upstream context keys' do
      error = described_class.new(
        'boom',
        upstream_status: 404,
        upstream_body: { 'error' => 'Item not found.' },
        upstream_headers: { 'x-request-id' => 'abc123' },
        failure_category: 'upstream_response'
      )

      expect(error.upstream_status).to eq(404)
      expect(error.upstream_body).to eq('error' => 'Item not found.')
      expect(error.upstream_headers).to eq('x-request-id' => 'abc123')
      expect(error.failure_category).to eq('upstream_response')
    end
  end

  describe '.client' do
    context 'in production' do
      before do
        allow(Rails.env).to receive(:production?).and_return(true)
        allow(Settings).to receive(:dig).and_call_original
        allow(Settings).to receive(:dig).with(:cave, :idp, :base_url).and_return('https://idp.example.com')
      end

      it 'returns the real client' do
        expect(Idp.client).to be_an_instance_of(Idp::Client)
      end
    end

    context 'in development' do
      before { allow(Rails.env).to receive(:production?).and_return(false) }

      it 'returns the mock client' do
        expect(Idp.client).to be_an_instance_of(Idp::MockClient)
      end
    end

    context 'when cave.idp.mock is nil outside production' do
      before do
        allow(Rails.env).to receive(:production?).and_return(false)
        allow(ENV).to receive(:[]).and_call_original
        allow(ENV).to receive(:[]).with('IDP_USE_LIVE').and_return(nil)
        allow(Settings).to receive(:dig).and_call_original
        allow(Settings).to receive(:dig).with(:cave, :idp, :mock).and_return(nil)
      end

      it 'defaults to the mock client' do
        expect(Idp.client).to be_an_instance_of(Idp::MockClient)
      end
    end

    context 'when cave.idp.mock is false outside production' do
      before do
        allow(Rails.env).to receive(:production?).and_return(false)
        allow(ENV).to receive(:[]).and_call_original
        allow(ENV).to receive(:[]).with('IDP_USE_LIVE').and_return(nil)
        allow(Settings).to receive(:dig).and_call_original
        allow(Settings).to receive(:dig).with(:cave, :idp, :mock).and_return(false)
        allow(Settings).to receive(:dig).with(:cave, :idp, :base_url).and_return('https://idp.example.com')
        allow(Settings).to receive(:dig).with(:cave, :idp, :timeout).and_return(15)
      end

      it 'returns the real client' do
        expect(Idp.client).to be_an_instance_of(Idp::Client)
      end
    end

    context 'when IDP_USE_LIVE is set' do
      before do
        allow(Rails.env).to receive(:production?).and_return(false)
        allow(ENV).to receive(:[]).and_call_original
        allow(ENV).to receive(:[]).with('IDP_USE_LIVE').and_return('true')
        allow(Settings).to receive(:dig).and_call_original
        allow(Settings).to receive(:dig).with(:cave, :idp, :base_url).and_return('https://idp.example.com')
      end

      it 'returns the real client even outside production' do
        expect(Idp.client).to be_an_instance_of(Idp::Client)
      end
    end
  end
end
