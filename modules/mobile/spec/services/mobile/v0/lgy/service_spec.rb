# frozen_string_literal: true

require 'rails_helper'
require 'mobile/v0/lgy/service'

describe Mobile::V0::Lgy::Service do
  subject { described_class.new(edipi: '1007697216', icn: '1012666073V986297') }

  describe 'configuration override' do
    it 'uses the mobile-specific configuration' do
      expect(subject.send(:config)).to be_a(Mobile::V0::Lgy::Configuration)
    end

    it 'injects the mobile appId and apiKey into the Authorization header' do
      with_settings(Settings.lgy_mobile, app_id: 'MOBILE_APP_ID', api_key: 'mobile-api-key') do
        expect(subject.request_headers[:Authorization])
          .to eq('api-key { "appId":"MOBILE_APP_ID", "apiKey": "mobile-api-key"}')
      end
    end

    it 'does not use the web (Settings.lgy) credentials' do
      with_settings(Settings.lgy, app_id: 'WEB_APP_ID', api_key: 'web-api-key') do
        with_settings(Settings.lgy_mobile, app_id: 'MOBILE_APP_ID', api_key: 'mobile-api-key') do
          expect(subject.request_headers[:Authorization]).not_to include('WEB_APP_ID', 'web-api-key')
        end
      end
    end
  end
end
