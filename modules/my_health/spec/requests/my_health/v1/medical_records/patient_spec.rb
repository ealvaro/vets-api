# frozen_string_literal: true

require 'rails_helper'
require 'support/mr_client_helpers'
require 'medical_records/client'
require 'medical_records/bb_internal/client'

RSpec.describe 'MyHealth::V1::MedicalRecords::Patient', type: :request do
  include MedicalRecords::ClientHelpers

  let(:va_patient) { true }
  let(:current_user) { build(:user, :mhv, va_patient:) }
  let(:bb_client) { instance_double(BBInternal::Client) }

  # Representative upstream MHV patient resource, including the sensitive and
  # unused top-level keys that must never be transmitted to the browser.
  let(:upstream_patient) do
    {
      'id' => 123,
      'icn' => '1000000000V000000',
      'correlationErrorCode' => nil,
      'invalidatedIcn' => nil,
      'correlatedBy' => 'system',
      'userProfileId' => 456,
      'ipas' => [{ 'id' => 1, 'status' => 'Authenticated', 'authenticatingFacilityId' => 789 }],
      'userProfile' => {
        'ssn' => '666-00-0000',
        'confSsn' => '666-00-0000',
        'userName' => 'veteran123',
        'passwordHintAnswer1' => 'secret'
      },
      'facilities' => [
        { 'id' => 10, 'facilityInfo' => { 'name' => 'Test VAMC', 'stationNumber' => '451', 'treatment' => true } }
      ],
      'patientRegistryChanges' => [{ 'oldSsn' => '666-11-1111', 'oldFirstName' => 'OLD' }]
    }
  end

  before do
    allow(MedicalRecords::Client).to receive(:new).and_return(authenticated_client)
    allow(BBInternal::Client).to receive(:new).and_return(bb_client)
    allow(bb_client).to receive(:authenticate)
    allow(bb_client).to receive(:get_patient).and_return(upstream_patient)
    sign_in_as(current_user)
  end

  describe 'GET #index' do
    it 'returns only the allowlisted facilities and ipas keys' do
      get '/my_health/v1/medical_records/patient'

      expect(response).to have_http_status(:ok)

      json = JSON.parse(response.body)
      expect(json.keys).to contain_exactly('facilities', 'ipas')
    end

    it 'does not return sensitive or unused top-level fields' do
      get '/my_health/v1/medical_records/patient'

      json = JSON.parse(response.body)
      unused_keys = %w[
        userProfile patientRegistryChanges icn correlationErrorCode
        invalidatedIcn correlatedBy userProfileId
      ]
      expect(json.keys & unused_keys).to be_empty
      expect(response.body).not_to include('666-00-0000') # SSN
      expect(response.body).not_to include('veteran123')  # MHV username
      expect(response.body).not_to include('666-11-1111') # historical SSN
    end

    it 'preserves the facilities and ipas payloads consumed by the frontend' do
      get '/my_health/v1/medical_records/patient'

      json = JSON.parse(response.body)
      expect(json['facilities']).to eq(upstream_patient['facilities'])
      expect(json['ipas']).to eq(upstream_patient['ipas'])
    end
  end
end
