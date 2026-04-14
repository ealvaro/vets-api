# frozen_string_literal: true

require_relative '../../../../support/helpers/rails_helper'
require_relative '../../../../support/helpers/committee_helper'

RSpec.describe 'Mobile::V0::Push::Register', type: :request do
  include CommitteeHelper

  let!(:user) { sis_user }
  let(:headers) { sis_headers(json: true) }

  describe 'PUT /mobile/v0/push/register' do
    context 'with a valid put body' do
      it 'matches the register schema' do
        params = {
          appName: 'va_mobile_app',
          deviceToken: '09d5a13a03b64b669f5ac0c32a0db6ad',
          osName: 'ios',
          deviceName: 'My Iphone',
          debug: false
        }
        VCR.use_cassette('vetext/register_success') do
          put '/mobile/v0/push/register', headers:, params: params.to_json
          expect(response).to have_http_status(:ok)
          assert_schema_conform(200)
        end
      end

      it 'with no device name matches the register schema' do
        params = {
          appName: 'va_mobile_app',
          deviceToken: '09d5a13a03b64b669f5ac0c32a0db6ad',
          osName: 'ios',
          debug: false
        }
        VCR.use_cassette('vetext/register_success') do
          put '/mobile/v0/push/register', headers:, params: params.to_json
          expect(response).to have_http_status(:ok)
          assert_schema_conform(200)
        end
      end
    end

    context 'with a valid put body and debug flag' do
      it 'matches the register schema' do
        params = {
          appName: 'va_mobile_app',
          deviceToken: '09d5a13a03b64b669f5ac0c32a0db6ad',
          osName: 'ios',
          deviceName: 'My Iphone',
          debug: true
        }
        VCR.use_cassette('vetext/register_success') do
          put '/mobile/v0/push/register', headers:, params: params.to_json
          expect(response).to have_http_status(:ok)
          assert_schema_conform(200)
        end
      end
    end

    context 'with invalid appName' do
      it 'matches the errors schema and responds not found' do
        params = {
          appName: 'bad_name',
          deviceToken: '09d5a13a03b64b669f5ac0c32a0db6ad',
          osName: 'ios',
          deviceName: 'My Iphone',
          debug: 'false'
        }
        put '/mobile/v0/push/register', headers:, params: params.to_json
        expect(response).to have_http_status(:not_found)
        assert_schema_conform(404)
      end
    end

    context 'with bad request' do
      it 'returns bad request and errors' do
        params = {
          appName: 'va_mobile_app',
          deviceToken: '9bad7c63574f75f46944c6436a01b7c41c0776d6f061aa46b0884cdd93bb6959',
          osName: 'ios',
          deviceName: 'My Iphone',
          debug: 'false'
        }
        VCR.use_cassette('vetext/register_bad_request') do
          put '/mobile/v0/push/register', headers:, params: params.to_json
          expect(response).to have_http_status(:bad_request)
          assert_schema_conform(400)
        end
      end
    end

    context 'when causing vetext internal server error' do
      it 'returns bad gateway and errors' do
        params = {
          appName: 'va_mobile_app',
          deviceToken: '9bad7c63574f75f46944c6436a01b7c41c0776d6f061aa46b0884cdd93bb6959',
          osName: 'ios',
          deviceName: 'My Iphone',
          debug: 'false'
        }
        VCR.use_cassette('vetext/register_internal_server_error') do
          put '/mobile/v0/push/register', headers:, params: params.to_json
          expect(response).to have_http_status(:bad_gateway)
          assert_schema_conform(502)
        end
      end
    end
  end
end
