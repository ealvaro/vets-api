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

  def stub_builder(builder_class, **overrides)
    account = MedicalCopays::FacilityAccounts::FacilityAccount.new(
      { station_id: '757', is_cerner: false, current_balance: 105.24 }.merge(overrides)
    )
    allow(builder_class).to receive(:new).and_return(
      instance_double(builder_class, build_facility_accounts: [account])
    )
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
      stub_builder(MedicalCopays::FacilityAccounts::VBSBuilder, station_id: '640', is_cerner: true)

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
end
