# frozen_string_literal: true

require 'rails_helper'
require 'github/installation_token_generator'

RSpec.describe Github::InstallationTokenGenerator do
  subject(:generator) { described_class.new(app_id:, private_key:, api_endpoint:) }

  let(:rsa_key) { OpenSSL::PKey::RSA.generate(2048) }
  let(:private_key) { rsa_key.to_pem }
  let(:app_id) { '123456' }
  let(:api_endpoint) { 'https://api.va.ghe.com' }
  let(:installation) { double(id: 789) }

  describe '#initialize' do
    it 'raises if app_id is missing' do
      expect { described_class.new(app_id: '', private_key:, api_endpoint:) }
        .to raise_error(ArgumentError, 'app_id is required')
    end

    it 'raises if private_key is missing' do
      expect { described_class.new(app_id:, private_key: '', api_endpoint:) }
        .to raise_error(ArgumentError, 'private_key is required')
    end

    it 'raises if api_endpoint is missing' do
      expect { described_class.new(app_id:, private_key:, api_endpoint: '') }
        .to raise_error(ArgumentError, 'api_endpoint is required')
    end

    it 'raises a clear error if private_key is malformed' do
      expect { described_class.new(app_id:, private_key: 'not-a-valid-rsa-key', api_endpoint:) }
        .to raise_error(ArgumentError, 'private_key is invalid')
    end
  end

  describe '#generate' do
    it 'raises if org is missing' do
      expect { generator.generate(org: '') }
        .to raise_error(ArgumentError, 'org is required')
    end

    it 'signs a JWT with the app id as issuer and exchanges it for an installation token' do
      client = instance_double(Octokit::Client)
      allow(Octokit::Client).to receive(:new).with(
        bearer_token: kind_of(String), api_endpoint:
      ).and_return(client)
      allow(client).to receive(:find_organization_installation).with('software').and_return(installation)
      allow(client).to receive(:create_app_installation_access_token).with(
        installation.id, accept: 'application/vnd.github+json'
      ).and_return({ token: 'v1.short-lived-token' })

      expect(generator.generate(org: 'software')).to eq('v1.short-lived-token')
    end

    it 'builds a JWT with the app_id as issuer and a short expiry' do
      captured_jwt = nil
      allow(Octokit::Client).to receive(:new) do |bearer_token:, **|
        captured_jwt = bearer_token
        instance_double(
          Octokit::Client,
          find_organization_installation: installation,
          create_app_installation_access_token: { token: 'v1.short-lived-token' }
        )
      end

      generator.generate(org: 'software')

      claims = JWT.decode(captured_jwt, rsa_key.public_key, true, algorithm: 'RS256').first
      expect(claims['iss']).to eq(app_id)
      expect(claims['exp'] - claims['iat']).to be <= 600
    end

    it 'creates a fresh app client for each generate call' do
      client_one = instance_double(Octokit::Client)
      client_two = instance_double(Octokit::Client)

      allow(Octokit::Client).to receive(:new).and_return(client_one, client_two)

      allow(client_one).to receive(:find_organization_installation).with('software').and_return(installation)
      allow(client_one).to receive(:create_app_installation_access_token).with(
        installation.id, accept: 'application/vnd.github+json'
      ).and_return({ token: 'v1.token-1' })

      allow(client_two).to receive(:find_organization_installation).with('software').and_return(installation)
      allow(client_two).to receive(:create_app_installation_access_token).with(
        installation.id, accept: 'application/vnd.github+json'
      ).and_return({ token: 'v1.token-2' })

      expect(generator.generate(org: 'software')).to eq('v1.token-1')
      expect(generator.generate(org: 'software')).to eq('v1.token-2')
      expect(Octokit::Client).to have_received(:new).twice
    end
  end
end
