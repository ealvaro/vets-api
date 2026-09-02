# frozen_string_literal: true

require_relative '../../../../support/helpers/rails_helper'
require 'mhv/aal/client'

RSpec.describe 'Mobile::V0::Health::LabsAndTests', type: :request do
  let!(:user) { sis_user(icn: '32000225') }

  let(:diagnostic_report_response) do
    [
      { 'id' => 'I2-EWSRFHMJRWT3KNBUB542ZJYEKM000000',
        'type' => 'diagnostic_report',
        'attributes' =>
          { 'category' => 'Laboratory',
            'code' => 'panel',
            'subject' => {
              'reference' => 'https://sandbox-api.va.gov/services/fhir/v0/r4/Patient/1000005',
              'display' => 'Mr. Shane235 Bartell116'
            },
            'effectiveDateTime' => '1998-03-16T05:56:37Z',
            'issued' => '1998-03-16T05:56:37Z',
            'result' => [
              {
                'reference' => 'http://www.example.com/mobile/v0/health/observations/I2-ILWORI4YUOUAR5H2GCH6ATEFRM000000',
                'display' => 'Glucose'
              },
              {
                'reference' => 'http://www.example.com/mobile/v0/health/observations/I2-6DTSU5DDGS3NBDOKN4BOZDISGE000000',
                'display' => 'Urea Nitrogen'
              },
              {
                'reference' => 'http://www.example.com/mobile/v0/health/observations/I2-4OWFD25REFR6P362ZJ2PY3ACWU000000',
                'display' => 'Creatinine'
              },
              {
                'reference' => 'http://www.example.com/mobile/v0/health/observations/I2-35GNQKPTBRNMPBTUGEF4F62HNI000000',
                'display' => 'Calcium'
              },
              {
                'reference' => 'http://www.example.com/mobile/v0/health/observations/I2-OOVHBIQFYCOORXPBB74H42FPJU000000',
                'display' => 'Sodium'
              },
              {
                'reference' => 'http://www.example.com/mobile/v0/health/observations/I2-C3P7YCD3DCX7KNRRR5DOKLDCGA000000',
                'display' => 'Potassium'
              },
              { 'reference' => 'http://www.example.com/mobile/v0/health/observations/I2-K4NGUOCHCS3ULYOFMDN5ZRJW6U000000',
                'display' => 'Chloride' },
              {
                'reference' => 'http://www.example.com/mobile/v0/health/observations/I2-D5TBNWZQSFRRBOBSBCC7QQRPQY000000',
                'display' => 'Carbon Dioxide'
              }
            ] } }
    ]
  end

  it 'responds to GET #index' do
    VCR.use_cassette('mobile/lighthouse_disability_rating/introspect_active') do
      VCR.use_cassette('rrd/lighthouse_diagnostic_reports') do
        get '/mobile/v0/health/labs-and-tests', headers: sis_headers
      end
    end

    expect(response).to be_successful
    expect(response.parsed_body['data']).to eq(diagnostic_report_response)
  end

  describe 'AAL logging' do
    it 'logs a mobile AAL "Lab and test results" view entry on a successful fetch' do
      allow(Flipper).to receive(:enabled?).and_call_original
      allow(Flipper).to receive(:enabled?)
        .with(:mhv_mobile_medical_records_aal_logging, anything).and_return(true)
      expect_any_instance_of(Mobile::V0::LabsAndTestsController)
        .to receive(:log_mhv_aal).with(Mobile::AALClientConcerns::ActivityTypes::LAB_AND_TEST_RESULTS)

      VCR.use_cassette('mobile/lighthouse_disability_rating/introspect_active') do
        VCR.use_cassette('rrd/lighthouse_diagnostic_reports') do
          get '/mobile/v0/health/labs-and-tests', headers: sis_headers
        end
      end
    end

    it 'does not affect the response when AAL logging fails (non-blocking)' do
      allow(Flipper).to receive(:enabled?).and_call_original
      allow(Flipper).to receive(:enabled?)
        .with(:mhv_mobile_medical_records_aal_logging, anything).and_return(true)
      failing_client = instance_double(AAL::MobileClient)
      allow(AAL::MobileClient).to receive(:new).and_return(failing_client)
      allow(failing_client).to receive(:authenticate).and_raise(StandardError.new('boom'))

      VCR.use_cassette('mobile/lighthouse_disability_rating/introspect_active') do
        VCR.use_cassette('rrd/lighthouse_diagnostic_reports') do
          get '/mobile/v0/health/labs-and-tests', headers: sis_headers
        end
      end

      expect(response).to be_successful
    end
  end

  describe 'schema contract validation' do
    let(:user_account) { create(:user_account) }

    before do
      user.user_account_uuid = user_account.id
      user.save!
    end

    context 'when in staging' do
      before do
        allow(Settings).to receive(:vsp_environment).and_return('staging')
      end

      it 'validates the schema for list_diagnostic_reports' do
        VCR.use_cassette('mobile/lighthouse_disability_rating/introspect_active') do
          VCR.use_cassette('rrd/lighthouse_diagnostic_reports') do
            get '/mobile/v0/health/labs-and-tests', headers: sis_headers
          end
        end

        expect(response).to be_successful
        SchemaContract::ValidationJob.drain
        expect(SchemaContract::Validation.last.status).to eq('success')
      end
    end

    context 'when in production' do
      before do
        allow(Settings).to receive(:vsp_environment).and_return('production')
      end

      it 'skips schema validation and does not create a record' do
        VCR.use_cassette('mobile/lighthouse_disability_rating/introspect_active') do
          VCR.use_cassette('rrd/lighthouse_diagnostic_reports') do
            get '/mobile/v0/health/labs-and-tests', headers: sis_headers
          end
        end

        expect(response).to be_successful
        expect(SchemaContract::Validation.count).to eq(0)
      end
    end
  end
end
