# frozen_string_literal: true

require 'rails_helper'
require 'sign_in/entra/configuration'

describe SignIn::Entra::Configuration do
  describe '#base_path' do
    subject { described_class.instance.base_path }

    it 'returns the tenant scoped oauth url' do
      expect(subject).to eq("#{IdentitySettings.entra.oauth_url}/#{IdentitySettings.entra.tenant_id}")
    end
  end

  describe '#redirect_uri' do
    subject { described_class.instance.redirect_uri }

    let(:review_instance_slug) { nil }

    before { allow(Settings).to receive(:review_instance_slug).and_return(review_instance_slug) }

    context 'when review_instance_slug is present' do
      let(:review_instance_slug) { 'some-review-instance-slug' }

      it 'returns the review instance callback proxy URI' do
        expect(subject).to eq(
          "https://staging-api.va.gov/#{SignIn::Constants::Auth::REVIEW_INSTANCE_CALLBACK_PROXY_PATH}"
        )
      end
    end

    context 'when review_instance_slug is not present' do
      it 'returns the entra redirect_uri from settings' do
        expect(subject).to eq(IdentitySettings.entra.redirect_uri)
      end
    end
  end

  describe '#client_cert_thumbprint' do
    subject { described_class.instance.client_cert_thumbprint }

    let(:cert) { OpenSSL::X509::Certificate.new(File.read(IdentitySettings.entra.client_cert_path)) }
    let(:expected_thumbprint) { Base64.urlsafe_encode64(OpenSSL::Digest::SHA1.digest(cert.to_der), padding: false) }

    it 'returns the base64url encoded sha1 thumbprint of the client cert' do
      expect(subject).to eq(expected_thumbprint)
    end
  end
end
