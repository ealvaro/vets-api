# frozen_string_literal: true

require 'rails_helper'

RSpec.describe SignIn::ErrorPageRenderer do
  subject(:renderer) { described_class.new(error_code:, request_id:, redirect_uri:) }

  let(:error_code) { '400' }
  let(:request_id) { 'some-request-id' }
  let(:redirect_uri) { 'https://va.gov/sign-in' }

  describe '#perform' do
    before do
      allow(IdentitySettings.sign_in).to receive(:usip_uri).and_return('https://staging.va.gov/sign-in')
    end

    it 'returns HTML containing the error code and request id' do
      html = renderer.perform
      expect(html).to include('some-request-id')
      expect(html).to include('400')
    end

    it 'includes the page title' do
      expect(renderer.perform).to include('Auth | Veterans Affairs')
    end

    it 'includes the alert text for the error code' do
      expect(renderer.perform).to include('Something went wrong on our end')
    end

    it 'includes the default section title' do
      expect(renderer.perform).to include('What you can do:')
    end

    it 'includes the redirect uri as a button link' do
      html = renderer.perform
      expect(html).to include('class="usa-button"')
      expect(html).to include('https://va.gov/sign-in')
    end

    it 'includes a timestamp' do
      Timecop.freeze(Time.zone.parse('2026-03-25 16:14:30 UTC')) do
        expect(renderer.perform).to include('Mar 25, 2026, 4:14:30 PM UTC')
      end
    end

    context 'when redirect_uri is nil' do
      let(:redirect_uri) { nil }

      it 'does not include a button' do
        expect(renderer.perform).not_to include('class="usa-button"')
      end

      it 'still includes the try again text' do
        expect(renderer.perform).to include('Try signing in again')
      end
    end

    context 'with error code 001' do
      let(:error_code) { '001' }

      it 'renders the verification denied content' do
        html = renderer.perform
        expect(html).to include('selected &quot;Deny&quot;')
        expect(html).to include('select &quot;Accept&quot;')
      end
    end

    context 'with error code 106' do
      let(:error_code) { '106' }

      it 'renders the custom section title' do
        expect(renderer.perform).to include('To fix this issue:')
      end
    end

    context 'with an unknown error code' do
      let(:error_code) { '999' }

      it 'renders default content' do
        html = renderer.perform
        expect(html).to include('temporary issue')
        expect(html).to include('manage your VA benefits over the phone')
      end
    end

    it 'includes the environment home URI in the header link' do
      html = renderer.perform
      expect(html).to include('href="https://staging.va.gov"')
    end

    context 'with error code 113' do
      let(:error_code) { '113' }

      context 'when error_113_tech_support_line_active is enabled' do
        before do
          allow(Flipper).to receive(:enabled?).with(:error_113_tech_support_line_active).and_return(true)
        end

        it 'renders the tech support call-to-action instead of the legacy issue-status message' do
          html = renderer.perform
          expect(html).to include('To request a fix, you&#39;ll need to call our technical support team.')
          expect(html).not_to include('We&#39;re working to fix it as soon as possible')
        end
      end

      context 'when error_113_tech_support_line_active is disabled' do
        before do
          allow(Flipper).to receive(:enabled?).with(:error_113_tech_support_line_active).and_return(false)
        end

        it 'renders the legacy issue-status message instead of the tech support call-to-action' do
          html = renderer.perform
          expect(html).to include('We&#39;re working to fix it as soon as possible')
          expect(html).not_to include('To request a fix, you&#39;ll need to call our technical support team.')
        end
      end
    end
  end
end
