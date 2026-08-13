# frozen_string_literal: true

require 'rails_helper'

RSpec.describe SignIn::DeviceParser do
  describe '#perform' do
    subject { described_class.new(user_agent).perform }

    context 'with an iPhone user agent (device resolves)' do
      let(:user_agent) do
        'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 ' \
          '(KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1'
      end

      it 'returns the browser and the device model as the description' do
        expect(subject[:browser]).to eq('Mobile Safari')
        expect(subject[:device_description]).to eq('iPhone')
      end
    end

    context 'with a desktop Windows user agent (no device, os resolves)' do
      let(:user_agent) do
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 ' \
          '(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36'
      end

      it 'returns the browser and falls back to OS + version' do
        expect(subject[:browser]).to eq('Chrome')
        expect(subject[:device_description]).to match(/\AWindows/)
      end
    end

    context 'with a desktop Mac user agent' do
      let(:user_agent) do
        'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 ' \
          '(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36'
      end

      it 'falls back to OS description when there is no device model' do
        expect(subject[:browser]).to eq('Chrome')
        expect(subject[:device_description]).to match(/Mac/)
      end
    end

    context 'when the user agent is nil' do
      let(:user_agent) { nil }

      it 'returns a hash of nils' do
        expect(subject).to eq(browser: nil, device_description: nil)
      end
    end

    context 'when the user agent is blank' do
      let(:user_agent) { '' }

      it 'returns a hash of nils' do
        expect(subject).to eq(browser: nil, device_description: nil)
      end
    end

    context 'when the user agent is unrecognized junk' do
      let(:user_agent) { 'not-a-real-user-agent-@@@' }

      it 'returns the "Other" sentinel for unresolved fields' do
        expect(subject[:browser]).to eq('Other')
        expect(subject[:device_description]).to eq('Other')
      end
    end

    context 'when the parser raises' do
      let(:user_agent) { 'anything' }

      before do
        allow(described_class::PARSER).to receive(:parse).and_raise(StandardError, 'boom')
      end

      it 'swallows the error and returns a hash of nils' do
        expect(subject).to eq(browser: nil, device_description: nil)
      end
    end
  end
end
