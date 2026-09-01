# frozen_string_literal: true

require 'rails_helper'
require 'support/sm_client_helpers'
require 'support/shared_examples_for_mhv'

RSpec.describe 'MyHealth::V1::Messaging::Allrecipients', type: :request do
  include SM::ClientHelpers
  include SchemaMatchers

  let(:current_user) { build(:user, :mhv) }

  before do
    sign_in_as(current_user, stub_mhv_account: true)
    Timecop.freeze(Time.zone.parse('2017-05-01T19:25:00Z'))
  end

  after do
    Timecop.return
  end

  context 'when NOT authorized' do
    let(:current_user) { build(:user, :mhv, mhv_account_creation: { sm_account_created: false }) }

    before do
      get '/my_health/v1/messaging/allrecipients'
    end

    include_examples 'for user account level', message: 'You do not have access to messaging'
  end

  context 'when facilities api call fails' do
    before do
      VCR.insert_cassette('sm_client/session')
    end

    after do
      VCR.eject_cassette
    end
  end

  context 'when authorized' do
    before do
      VCR.insert_cassette('sm_client/session')
    end

    after do
      VCR.eject_cassette
    end

    it 'replaces missing health care system names in non-prod environments' do
      VCR.use_cassette('sm_client/triage_teams/gets_all_triage_team_recipients_missing_system_names') do
        get '/my_health/v1/messaging/allrecipients'
      end

      expect(response).to be_successful
      resp_body = JSON.parse(response.body)
      expect(resp_body['data'][0]['attributes']['station_number']).to eq('660')
      expect(resp_body['data'][0]['attributes']['health_care_system_name']).to eq('VA Salt Lake City health care')
    end

    it 'replaces missing health care system ids in prod environment' do
      VCR.use_cassette('sm_client/triage_teams/gets_all_triage_team_recipients_vha_612') do
        get '/my_health/v1/messaging/allrecipients'
      end

      expect(response).to be_successful
      resp_body = JSON.parse(response.body)
      expect(resp_body['data'][0]['attributes']['station_number']).to eq('612A4')
    end

    it 'replaces health care system names for hardcoded stations' do
      # rubocop:disable Layout/LineLength
      VCR.use_cassette('sm_client/triage_teams/gets_a_collection_of_all_triage_team_recipients_include_complex_teams') do
        get '/my_health/v1/messaging/allrecipients'
      end
      # rubocop:enable Layout/LineLength
      expect(response).to be_successful
      resp_body = JSON.parse(response.body)
      resp_body['data'].each do |team|
        station_number = team['attributes']['station_number']
        expected_name = MyHealth::FacilitiesHelper::COMPLICATED_SYSTEMS[station_number]
        expect(team['attributes']['health_care_system_name']).to eq(expected_name) if expected_name
      end
    end

    it 'applies non-prod system name override and converts station_numbers' do
      VCR.use_cassette('sm_client/triage_teams/gets_a_collection_of_all_triage_team_recipients') do
        get '/my_health/v1/messaging/allrecipients'
      end

      expect(response).to be_successful
      resp_body = JSON.parse(response.body)
      expect(resp_body['data'][0]['attributes']['station_number']).to eq('660')
      expect(resp_body['data'][0]['attributes']['health_care_system_name']).to eq('VA Salt Lake City health care')
    end

    it 'responds to GET #index' do
      VCR.use_cassette('sm_client/triage_teams/gets_a_collection_of_all_triage_team_recipients') do
        get '/my_health/v1/messaging/allrecipients'
      end

      expect(response).to be_successful
      expect(response.body).to be_a(String)
      expect(response).to match_response_schema('my_health/messaging/v1/all_triage_teams')
    end

    it 'responds to GET #index when camel-inflected' do
      VCR.use_cassette('sm_client/triage_teams/gets_a_collection_of_all_triage_team_recipients') do
        get '/my_health/v1/messaging/allrecipients', headers: { 'X-Key-Inflection' => 'camel' }
      end

      expect(response).to be_successful
      expect(response.body).to be_a(String)
      expect(response).to match_camelized_response_schema('my_health/messaging/v1/all_triage_teams')
    end

    it 'when resource is blank returns 404 RecordNotFound' do
      allow(StatsD).to receive(:increment)
      allow_any_instance_of(SM::Client).to receive(:get_all_triage_teams).and_return(nil)

      get '/my_health/v1/messaging/allrecipients'

      expect(StatsD).to have_received(:increment).with('api.my_health.all_triage_teams.fail')
      expect(response).to have_http_status(:not_found)
      expect(response.body).to include('Triage teams for user ID')
    end
  end

  context 'with requires_oh flag enabled' do
    it 'responds to GET #index with requires_oh flipper' do
      allow(Flipper).to receive(:enabled?)
        .with(:mhv_secure_messaging_cerner_pilot, anything)
        .and_return(true)

      VCR.use_cassette('sm_client/session_require_oh') do
        VCR.use_cassette('sm_client/triage_teams/gets_a_collection_of_all_triage_team_recipients_require_oh') do
          get '/my_health/v1/messaging/allrecipients'
        end
      end

      expect(response).to be_successful
      expect(response.body).to be_a(String)
      expect(response).to match_response_schema('my_health/messaging/v1/all_triage_teams')
    end
  end

  context 'VTG filtering' do
    before do
      sign_in_as(current_user, stub_mhv_account: true)
      VCR.insert_cassette('sm_client/session')
      allow(Flipper).to receive(:enabled?).with(:mhv_secure_messaging_show_vtgs_web, anything).and_return(false)
      allow(Flipper).to receive(:enabled?).with(:mhv_secure_messaging_hide_pretransitioned_vtgs,
                                                anything).and_return(false)
    end

    after do
      VCR.eject_cassette
    end

    it 'filters VTGs by default when toggle is off' do
      expect_any_instance_of(SM::Client).to receive(:get_all_triage_teams)
        .with(anything, filter_non_pretransitioned_vtgs: true, filter_pretransitioned_vtgs: false)
        .and_call_original

      VCR.use_cassette('sm_client/triage_teams/gets_a_collection_of_all_triage_team_recipients') do
        get '/my_health/v1/messaging/allrecipients'
      end

      expect(response).to be_successful
    end

    it 'excludes VTGs from the response when toggle is off' do
      VCR.use_cassette('sm_client/triage_teams/gets_all_triage_teams_with_virtual_groups') do
        get '/my_health/v1/messaging/allrecipients'
      end

      expect(response).to be_successful
      resp_body = JSON.parse(response.body)
      returned_ids = resp_body['data'].map { |t| t['attributes']['triage_team_id'] }

      # Known VTG triage team IDs should NOT be present (filtered out)
      expect(returned_ids).not_to include(6_725_162) # SM668 CANCER CARE (VTG at 668)
      expect(returned_ids).not_to include(6_692_633) # Columbus VTG at 757

      # Known non-VTG triage team IDs SHOULD be present
      expect(returned_ids).to include(6_238_822) # VHA SPO ALS (non-VTG at 668)
      expect(returned_ids).to include(6_238_639) # VHA COS Allergy (non-VTG at 757)

      # Both stations should still have teams in the response
      stations = resp_body['data'].map { |t| t['attributes']['station_number'] }.uniq.sort
      expect(stations).to eq(%w[668 757])
    end

    it 'includes VTGs when show_vtgs_web toggle is enabled' do
      allow(Flipper).to receive(:enabled?).with(:mhv_secure_messaging_show_vtgs_web, anything).and_return(true)

      VCR.use_cassette('sm_client/triage_teams/gets_all_triage_teams_with_virtual_groups') do
        get '/my_health/v1/messaging/allrecipients'
      end

      expect(response).to be_successful
      resp_body = JSON.parse(response.body)
      returned_ids = resp_body['data'].map { |t| t['attributes']['triage_team_id'] }

      # Known VTG triage team IDs SHOULD now be present (not filtered)
      expect(returned_ids).to include(6_725_162) # SM668 CANCER CARE (VTG at 668)
      expect(returned_ids).to include(6_692_633) # Columbus VTG at 757
    end

    it 'hides all VTGs when hide_pretransitioned_vtgs toggle is on' do
      allow(Flipper).to receive(:enabled?).with(:mhv_secure_messaging_hide_pretransitioned_vtgs,
                                                anything).and_return(true)

      # Add station 668 to pretransitioned list — normally its VTGs would be kept
      allow(Settings.mhv.oh_facility_checks).to receive(:pretransitioned_oh_facilities)
        .and_return('612, 357, 555, 668')

      VCR.use_cassette('sm_client/triage_teams/gets_all_triage_teams_with_virtual_groups') do
        get '/my_health/v1/messaging/allrecipients'
      end

      expect(response).to be_successful
      resp_body = JSON.parse(response.body)
      returned_ids = resp_body['data'].map { |t| t['attributes']['triage_team_id'] }

      # ALL VTGs should be removed (non-pretransitioned filtered by show_vtgs_web=off, pretransitioned by this toggle)
      expect(returned_ids).not_to include(6_725_162) # SM668 CANCER CARE (VTG at 668)
      expect(returned_ids).not_to include(6_692_633) # Columbus VTG at 757

      # Non-VTG teams should still be present
      expect(returned_ids).to include(6_238_822) # VHA SPO ALS (non-VTG at 668)
      expect(returned_ids).to include(6_238_639) # VHA COS Allergy (non-VTG at 757)
    end

    it 'hides pretransitioned VTGs but shows non-pretransitioned VTGs when both toggles are on' do
      allow(Flipper).to receive(:enabled?).with(:mhv_secure_messaging_show_vtgs_web, anything).and_return(true)
      allow(Flipper).to receive(:enabled?).with(:mhv_secure_messaging_hide_pretransitioned_vtgs,
                                                anything).and_return(true)

      # Add station 668 to pretransitioned list
      allow(Settings.mhv.oh_facility_checks).to receive(:pretransitioned_oh_facilities)
        .and_return('612, 357, 555, 668')

      VCR.use_cassette('sm_client/triage_teams/gets_all_triage_teams_with_virtual_groups') do
        get '/my_health/v1/messaging/allrecipients'
      end

      expect(response).to be_successful
      resp_body = JSON.parse(response.body)
      returned_ids = resp_body['data'].map { |t| t['attributes']['triage_team_id'] }

      # Pretransitioned VTG at 668 should be hidden (hide_pretransitioned is on)
      expect(returned_ids).not_to include(6_725_162) # SM668 CANCER CARE (VTG at 668)

      # Non-pretransitioned VTG at 757 should be shown (show_vtgs_web is on)
      expect(returned_ids).to include(6_692_633) # Columbus VTG at 757
    end
  end
end
