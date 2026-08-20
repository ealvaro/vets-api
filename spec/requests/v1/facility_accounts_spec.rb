# frozen_string_literal: true

require 'rails_helper'
require 'medical_copays/cerner_facilities'

RSpec.describe 'V1::FacilityAccounts', type: :request do
  let(:current_user) { build(:user, :loa3, icn: '123') }

  before do
    sign_in_as(current_user)
    allow(Flipper).to receive(:enabled?).with(:enable_facility_account_history, anything).and_return(true)
    allow(Flipper).to receive(:enabled?).with(:enable_lighthouse_copays, anything).and_return(true)
    allow(MedicalCopays::CernerFacilities).to receive(:cerner_copay_user?).and_return(false)
  end

  def get_facilities
    get '/v1/medical_copays/facilities'
  end

  def get_facility_account(station_id = '757')
    get "/v1/medical_copays/facility/#{station_id}"
  end

  def facility_account(**overrides)
    MedicalCopays::FacilityAccounts::FacilityAccount.new(
      { station_id: '757', is_cerner: false, current_balance: 105.24 }.merge(overrides)
    )
  end

  def stub_builder(builder_class, account = facility_account)
    allow(builder_class).to receive(:new).and_return(
      instance_double(builder_class, build_facility_accounts: [account], build_facility_account: account)
    )
  end

  def disable_feature_flag
    allow(Flipper).to receive(:enabled?).with(:enable_facility_account_history, anything).and_return(false)
  end

  describe 'GET /v1/medical_copays/facilities' do
    it 'serves a non-Cerner user from Lighthouse' do
      stub_builder(MedicalCopays::FacilityAccounts::LighthouseBuilder)

      get_facilities

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['totalCurrentBalance']).to eq(105.24)
      expect(response.parsed_body['facilities'].first['isCerner']).to be false
    end

    it 'serves a Cerner user from VBS' do
      allow(MedicalCopays::CernerFacilities).to receive(:cerner_copay_user?).and_return(true)
      stub_builder(MedicalCopays::FacilityAccounts::VBSBuilder, facility_account(station_id: '640', is_cerner: true))

      get_facilities

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['facilities'].first['isCerner']).to be true
    end

    it 'rejects a flagged-off request before building the service' do
      allow(Flipper).to receive(:enabled?).with(:enable_facility_account_history, anything).and_return(false)
      allow(MedicalCopays::FacilityAccounts::Service).to receive(:new)

      get_facilities

      expect(response).to have_http_status(:forbidden)
      expect(MedicalCopays::FacilityAccounts::Service).not_to have_received(:new)
    end

    it 'returns the standard 502 envelope when an upstream copay service fails' do
      builder = instance_double(MedicalCopays::FacilityAccounts::LighthouseBuilder)
      allow(builder).to receive(:build_facility_accounts).and_raise(MedicalCopays::VBS::Service::ServiceError)
      allow(MedicalCopays::FacilityAccounts::LighthouseBuilder).to receive(:new).and_return(builder)

      get_facilities

      expect(response).to have_http_status(:bad_gateway)
      expect(response.parsed_body['errors'].first).to include('code' => '502')
    end
  end

  describe 'GET /v1/medical_copays/facility/:facility_id' do
    context 'with a fully populated facility account' do
      before do
        stub_builder(
          MedicalCopays::FacilityAccounts::LighthouseBuilder,
          facility_account(facility_name: 'Chalmers P. Wylie Veterans Outpatient Clinic',
                           account_number: '123456', current_balance: 105.24, past_due_balance: 0.0,
                           statement_date: Date.new(2025, 12, 11), due_date: Date.new(2026, 1, 5),
                           transactions: [{ id: 'B1', type: 'charge', date: '2025-12-01',
                                            description: 'RX COPAY', amount: 105.24,
                                            billing_reference: 'H1234', provider: 'Dr X',
                                            medication: { medication_name: 'ATORVASTATIN', rx_number: '2719324',
                                                          quantity: 30, days_supply: 30 } }])
        )
      end

      it 'returns exactly the body documented in swagger' do
        get_facility_account

        expect(response).to have_http_status(:ok)
        expect(response.parsed_body).to eq(
          'stationId' => '757',
          'facilityName' => 'Chalmers P. Wylie Veterans Outpatient Clinic',
          'isCerner' => false,
          'accountNumber' => '123456',
          'currentBalance' => 105.24,
          'pastDueBalance' => 0.0,
          'statementDate' => '2025-12-11',
          'dueDate' => '2026-01-05',
          'transactions' => [
            { 'id' => 'B1', 'type' => 'charge', 'date' => '2025-12-01', 'description' => 'RX COPAY',
              'amount' => 105.24, 'billingReference' => 'H1234', 'provider' => 'Dr X',
              'medication' => { 'medicationName' => 'ATORVASTATIN', 'rxNumber' => '2719324',
                                'quantity' => 30, 'daysSupply' => 30 } }
          ]
        )
      end
    end

    it 'asks the builder for the station in the path' do
      builder = instance_double(MedicalCopays::FacilityAccounts::LighthouseBuilder,
                                build_facility_account: facility_account)
      allow(MedicalCopays::FacilityAccounts::LighthouseBuilder).to receive(:new).and_return(builder)

      get_facility_account('534')

      expect(builder).to have_received(:build_facility_account).with('534')
    end

    context 'with a Cerner user' do
      before do
        allow(MedicalCopays::CernerFacilities).to receive(:cerner_copay_user?).and_return(true)
        stub_builder(MedicalCopays::FacilityAccounts::VBSBuilder,
                     facility_account(station_id: '640', is_cerner: true))
      end

      it 'returns the facility account from VBS' do
        get_facility_account('640')

        expect(response).to have_http_status(:ok)
        expect(response.parsed_body['isCerner']).to be true
      end
    end

    it 'returns 404 when the user has no account at that station' do
      stub_builder(MedicalCopays::FacilityAccounts::LighthouseBuilder, nil)

      get_facility_account

      expect(response).to have_http_status(:not_found)
      expect(response.parsed_body['errors'].first).to include('code' => '404')
    end

    it 'returns 403 when the feature flag is disabled' do
      disable_feature_flag

      get_facility_account

      expect(response).to have_http_status(:forbidden)
    end

    context 'when an upstream copay service fails' do
      before do
        builder = instance_double(MedicalCopays::FacilityAccounts::LighthouseBuilder)
        allow(builder).to receive(:build_facility_account).and_raise(MedicalCopays::VBS::Service::ServiceError)
        allow(MedicalCopays::FacilityAccounts::LighthouseBuilder).to receive(:new).and_return(builder)
      end

      it 'returns the standard 502 envelope' do
        get_facility_account

        expect(response).to have_http_status(:bad_gateway)
        expect(response.parsed_body['errors'].first).to include('code' => '502')
      end
    end
  end
end
