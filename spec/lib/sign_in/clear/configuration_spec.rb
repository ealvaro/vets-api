# frozen_string_literal: true

require 'rails_helper'
require 'sign_in/clear/configuration'

describe SignIn::Clear::Configuration do
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
      it 'returns the clear redirect_uri from settings' do
        expect(subject).to eq(IdentitySettings.clear.redirect_uri)
      end
    end
  end

  describe '#verification_session_path' do
    subject { described_class.instance.verification_session_path(verification_id) }

    let(:verification_id) { 'verify_abc123' }

    it 'builds the v1 verification session path' do
      expect(subject).to eq('v1/verification_sessions/verify_abc123')
    end
  end
end
