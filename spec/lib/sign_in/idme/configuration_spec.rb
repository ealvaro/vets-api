# frozen_string_literal: true

require 'rails_helper'
require 'sign_in/idme/configuration'

describe SignIn::Idme::Configuration do
  describe '#redirect_uri' do
    subject { described_class.instance.redirect_uri }

    let(:review_instance_slug) { nil }

    before { allow(Settings).to receive(:review_instance_slug).and_return(review_instance_slug) }

    context 'when review_instance_slug is present' do
      let(:review_instance_slug) { 'some-review-instance-slug' }
      let(:hostname) { 'staging-api.va.gov' }

      before do
        allow(Settings).to receive_messages(review_instance_slug:, hostname:)
      end

      it 'returns the review instance callback proxy URI' do
        expect(subject).to eq(
          "https://staging-api.va.gov/#{SignIn::Constants::Auth::REVIEW_INSTANCE_CALLBACK_PROXY_PATH}"
        )
      end
    end

    context 'when review_instance_slug is not present' do
      it 'returns the idme redirect_uri from settings' do
        expect(subject).to eq(IdentitySettings.idme.redirect_uri)
      end
    end
  end
end
