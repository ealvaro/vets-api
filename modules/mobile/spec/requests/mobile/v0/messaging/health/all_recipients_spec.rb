# frozen_string_literal: true

require_relative '../../../../../support/helpers/rails_helper'
require 'sm/client'

RSpec.describe 'Mobile::V0::Messaging::Health::AllRecipients', type: :request do
  include SchemaMatchers

  let!(:user) { sis_user(:mhv, mhv_correlation_id: '123') }

  before do
    Timecop.freeze(Time.zone.parse('2017-05-01T19:25:00Z'))
  end

  after do
    Timecop.return
  end

  context 'when not authorized' do
    let!(:user) { sis_user(:mhv, mhv_account_creation: { sm_account_created: false }) }

    it 'responds with 403 error' do
      get '/mobile/v0/messaging/health/allrecipients', headers: sis_headers
      expect(response).to have_http_status(:forbidden)
    end
  end

  context 'when authorized' do
    before do
      VCR.insert_cassette('sm_client/session')
      allow_any_instance_of(SM::Client).to receive(:get_triage_teams_station_numbers).and_return([])
    end

    after do
      VCR.eject_cassette
    end

    it 'responds to GET #all_recipients' do
      VCR.use_cassette('sm_client/triage_teams/gets_a_collection_of_all_triage_team_recipients') do
        get '/mobile/v0/messaging/health/allrecipients', headers: sis_headers
      end
      expect(response).to be_successful
      expect(response.body).to be_a(String)
      expect(response).to match_camelized_response_schema('all_triage_teams')
    end

    context 'when suggestedNameDisplay is present' do
      it 'uses suggestedNameDisplay to override name' do
        VCR.use_cassette('sm_client/triage_teams/gets_a_collection_of_all_triage_team_recipients') do
          get '/mobile/v0/messaging/health/allrecipients', headers: sis_headers
        end
        expect(response).to be_successful
        triage_team = response.parsed_body['data'].find { |entry| entry['id'] == '4399547' }
        expected_name = 'Robert J. Dole VA Medical And Regional Office Center' \
                        ' | Pharmacy | Ask a pharmacist | SLC10 - James, Donald Sr'
        expect(triage_team.dig('attributes', 'name')).to eq(expected_name)
      end
    end

    it 'filters out teams with blocked_status == true' do
      VCR.use_cassette('sm_client/triage_teams/gets_a_collection_of_all_triage_team_recipients_include_blocked') do
        get '/mobile/v0/messaging/health/allrecipients', headers: sis_headers
      end
      expect(response).to be_successful
      expect(response.parsed_body['data'].count).to eq(1)
      expect(response).to match_camelized_response_schema('all_triage_teams')
    end

    it 'responds to GET #index with requires_oh flipper enabled and returns correct care systems' do
      allow(Flipper).to receive(:enabled?)
        .with(:mhv_secure_messaging_cerner_pilot, anything)
        .and_return(true)
      VCR.use_cassette('sm_client/session_require_oh') do
        VCR.use_cassette('sm_client/triage_teams/gets_a_collection_of_all_triage_team_recipients_require_oh') do
          get '/mobile/v0/messaging/health/allrecipients', headers: sis_headers
        end
      end

      parsed_response_meta = response.parsed_body['meta']
      care_systems = parsed_response_meta['careSystems']
      expect(care_systems.length).to be(3)
      expect(care_systems[0]['healthCareSystemName']).to eq('VA Wichita Health Care')
      expect(care_systems[0]['stationNumber']).to eq('977')
      expect(care_systems[1]['healthCareSystemName']).to eq('VA Wichita Health Care')
      expect(care_systems[1]['stationNumber']).to eq('978')
      expect(care_systems[2]['healthCareSystemName']).to eq('VA Dayton health care')
      expect(care_systems[2]['stationNumber']).to eq('552')
      expect(response).to be_successful
      expect(response.body).to be_a(String)
      expect(response).to match_camelized_response_schema('all_triage_teams', { strict: false })
    end

    context 'when stubbing get_all_triage_teams' do
      let(:params) { { useCache: true } }

      before do
        path = Rails.root.join('modules', 'mobile', 'spec', 'support', 'fixtures', 'all_triage_teams.json')
        data = Vets::Collection.new(JSON.parse(File.read(path)), AllTriageTeams)
        MyHealth::FacilitiesHelper.set_health_care_system_names(data)
        allow_any_instance_of(SM::Client).to receive(:get_all_triage_teams).and_return(data)
      end

      it 'retrieves triage teams from the stubbed client' do
        get('/mobile/v0/messaging/health/allrecipients', headers: sis_headers, params:)
        expect(response).to be_successful
        expect(response.body).to be_a(String)
        parsed_response_contents = response.parsed_body['data']
        triage_team = parsed_response_contents.select { |entry| entry['id'] == '4399547' }[0]
        expect(triage_team.dig('attributes', 'name')).to eq(
          'Robert J. Dole VA Medical And Regional Office Center | Pharmacy | Ask a pharmacist | SLC10 - James, Donald Sr' # rubocop:disable Layout/LineLength
        )
        expect(triage_team['type']).to eq('all_triage_teams')
        expect(response).to match_camelized_response_schema('all_triage_teams', { strict: false })
      end

      context 'when suggested_name_display is nil' do
        it 'falls back to name' do
          # Override the fixture data to have a nil suggested_name_display for the first team
          path = Rails.root.join('modules', 'mobile', 'spec', 'support', 'fixtures', 'all_triage_teams.json')
          fixture_data = JSON.parse(File.read(path))
          fixture_data.first['suggested_name_display'] = nil
          data = Vets::Collection.new(fixture_data, AllTriageTeams)
          MyHealth::FacilitiesHelper.set_health_care_system_names(data)
          allow_any_instance_of(SM::Client).to receive(:get_all_triage_teams).and_return(data)

          get('/mobile/v0/messaging/health/allrecipients', headers: sis_headers, params:)
          expect(response).to be_successful
          parsed_response_contents = response.parsed_body['data']
          triage_team = parsed_response_contents.select { |entry| entry['id'] == '4399547' }[0]
          expect(triage_team.dig('attributes', 'name')).to eq('589GR Pharmacy Ask a pharmacist SLC10 JAMES, DON')
        end
      end
    end

    context 'when there are multiple triage groups at the same care system' do
      let(:params) { { useCache: true } }

      before do
        path = Rails.root.join('modules', 'mobile', 'spec', 'support', 'fixtures',
                               'all_triage_teams_with_duplicates.json')
        data = Vets::Collection.new(JSON.parse(File.read(path)), AllTriageTeams)
        MyHealth::FacilitiesHelper.set_health_care_system_names(data)
        allow_any_instance_of(SM::Client).to receive(:get_all_triage_teams).and_return(data)
      end

      it 'returns a list of the name and station number for each unique care system in meta' do
        get('/mobile/v0/messaging/health/allrecipients', headers: sis_headers, params:)
        expect(response).to be_successful
        expect(response.body).to be_a(String)
        parsed_response_meta = response.parsed_body['meta']
        care_systems = parsed_response_meta['careSystems']
        expect(care_systems.length).to be(10)
        expect(care_systems[0]['healthCareSystemName']).to eq('VA Kansas City Health Care')
        expect(care_systems[0]['stationNumber']).to eq('977')
        # rubocop:disable Layout/LineLength
        expect(care_systems[1]['healthCareSystemName']).to eq('VA Northern California Healthcare (multiple facilities)')
        expect(care_systems[1]['stationNumber']).to eq('612A4')
        expect(care_systems[2]['healthCareSystemName']).to eq('VA Columbus Health Care')
        expect(care_systems[2]['stationNumber']).to eq('978')
        expect(care_systems[3]['healthCareSystemName']).to eq('VA Dayton health care')
        expect(care_systems[3]['stationNumber']).to eq('552')
        expect(care_systems[4]['healthCareSystemName']).to eq('VA New York State Healthcare (multiple facilities)')
        expect(care_systems[4]['stationNumber']).to eq('528')
        expect(care_systems[5]['healthCareSystemName']).to eq('VA Hudson Valley New York Healthcare (multiple facilities)')
        expect(care_systems[5]['stationNumber']).to eq('620')
        expect(care_systems[6]['healthCareSystemName']).to eq('VA Missouri and Illinois Healthcare (multiple facilities)')
        expect(care_systems[6]['stationNumber']).to eq('657')
        expect(care_systems[7]['healthCareSystemName']).to eq('VA Kansas and Missouri Healthcare (multiple facilities)')
        expect(care_systems[7]['stationNumber']).to eq('589')
        expect(care_systems[8]['healthCareSystemName']).to eq('VA Tennessee Healthcare (multiple facilities)')
        expect(care_systems[8]['stationNumber']).to eq('626')
        expect(care_systems[9]['healthCareSystemName']).to eq('VA Nebraska and Iowa Healthcare (multiple facilities)')
        expect(care_systems[9]['stationNumber']).to eq('636')
        # rubocop:enable Layout/LineLength
      end
    end

    context 'VTG filtering' do
      before do
        allow(Flipper).to receive(:enabled?).with(:mhv_secure_messaging_show_vtgs_mobile, anything).and_return(false)
        allow(Flipper).to receive(:enabled?).with(:mhv_secure_messaging_hide_pretransitioned_vtgs,
                                                  anything).and_return(false)
      end

      context 'when toggle is off' do
        it 'filters VTGs by default' do
          expect_any_instance_of(SM::Client).to receive(:get_all_triage_teams)
            .with(anything, filter_non_pretransitioned_vtgs: true, filter_pretransitioned_vtgs: false)
            .and_call_original

          VCR.use_cassette('sm_client/triage_teams/gets_a_collection_of_all_triage_team_recipients') do
            get '/mobile/v0/messaging/health/allrecipients', headers: sis_headers
          end

          expect(response).to be_successful
        end

        it 'excludes VTGs from the response' do
          VCR.use_cassette('sm_client/triage_teams/gets_all_triage_teams_with_virtual_groups') do
            get '/mobile/v0/messaging/health/allrecipients', headers: sis_headers
          end

          expect(response).to be_successful
          resp_body = response.parsed_body
          returned_ids = resp_body['data'].map { |t| t['attributes']['triageTeamId'] }

          # Known VTG triage team IDs should NOT be present (filtered out)
          expect(returned_ids).not_to include(6_725_162) # SM668 CANCER CARE (VTG at 668)
          expect(returned_ids).not_to include(6_692_633) # Columbus VTG at 757

          # Known non-VTG triage team IDs SHOULD be present
          expect(returned_ids).to include(6_238_822) # VHA SPO ALS (non-VTG at 668)
          expect(returned_ids).to include(6_238_639) # VHA COS Allergy (non-VTG at 757)

          # Both stations should still have teams in the response
          stations = resp_body['data'].map { |t| t['attributes']['stationNumber'] }.uniq.sort
          expect(stations).to eq(%w[668 757])
        end
      end

      context 'when show_vtgs_mobile toggle is enabled' do
        before do
          allow(Flipper).to receive(:enabled?).with(:mhv_secure_messaging_show_vtgs_mobile,
                                                    anything).and_return(true)
        end

        it 'includes VTGs' do
          VCR.use_cassette('sm_client/triage_teams/gets_all_triage_teams_with_virtual_groups') do
            get '/mobile/v0/messaging/health/allrecipients', headers: sis_headers
          end

          expect(response).to be_successful
          resp_body = response.parsed_body
          returned_ids = resp_body['data'].map { |t| t['attributes']['triageTeamId'] }

          # Known VTG triage team IDs SHOULD now be present (not filtered)
          expect(returned_ids).to include(6_725_162) # SM668 CANCER CARE (VTG at 668)
          expect(returned_ids).to include(6_692_633) # Columbus VTG at 757
        end
      end

      context 'when hide_pretransitioned_vtgs toggle is on' do
        before do
          allow(Flipper).to receive(:enabled?).with(:mhv_secure_messaging_hide_pretransitioned_vtgs,
                                                    anything).and_return(true)

          # Add station 668 to pretransitioned list — normally its VTGs would be kept
          allow(Settings.mhv.oh_facility_checks).to receive(:pretransitioned_oh_facilities)
            .and_return('612, 357, 555, 668')
        end

        it 'hides all VTGs' do
          VCR.use_cassette('sm_client/triage_teams/gets_all_triage_teams_with_virtual_groups') do
            get '/mobile/v0/messaging/health/allrecipients', headers: sis_headers
          end

          expect(response).to be_successful
          resp_body = response.parsed_body
          returned_ids = resp_body['data'].map { |t| t['attributes']['triageTeamId'] }

          # ALL VTGs should be removed
          # (non-pretransitioned filtered by show_vtgs_mobile=off, pretransitioned by this toggle)
          expect(returned_ids).not_to include(6_725_162) # SM668 CANCER CARE (VTG at 668)
          expect(returned_ids).not_to include(6_692_633) # Columbus VTG at 757

          # Non-VTG teams should still be present
          expect(returned_ids).to include(6_238_822) # VHA SPO ALS (non-VTG at 668)
          expect(returned_ids).to include(6_238_639) # VHA COS Allergy (non-VTG at 757)
        end
      end

      context 'when both toggles are on' do
        before do
          allow(Flipper).to receive(:enabled?).with(:mhv_secure_messaging_show_vtgs_mobile,
                                                    anything).and_return(true)
          allow(Flipper).to receive(:enabled?).with(:mhv_secure_messaging_hide_pretransitioned_vtgs,
                                                    anything).and_return(true)

          # Add station 668 to pretransitioned list
          allow(Settings.mhv.oh_facility_checks).to receive(:pretransitioned_oh_facilities)
            .and_return('612, 357, 555, 668')
        end

        it 'hides pretransitioned VTGs but shows non-pretransitioned VTGs' do
          VCR.use_cassette('sm_client/triage_teams/gets_all_triage_teams_with_virtual_groups') do
            get '/mobile/v0/messaging/health/allrecipients', headers: sis_headers
          end

          expect(response).to be_successful
          resp_body = response.parsed_body
          returned_ids = resp_body['data'].map { |t| t['attributes']['triageTeamId'] }

          # Pretransitioned VTG at 668 should be hidden (hide_pretransitioned is on)
          expect(returned_ids).not_to include(6_725_162) # SM668 CANCER CARE (VTG at 668)

          # Non-pretransitioned VTG at 757 should be shown (show_vtgs_mobile is on)
          expect(returned_ids).to include(6_692_633) # Columbus VTG at 757
        end
      end
    end

    describe 'schema contract validation' do
      let(:user_account) { create(:user_account) }

      before do
        user.user_account_uuid = user_account.id
        user.save!
      end

      context 'when in the staging environment' do
        before do
          allow(Settings).to receive(:vsp_environment).and_return('staging')
        end

        it 'validates schema for get_all_triage_teams' do
          VCR.use_cassette('sm_client/triage_teams/gets_a_collection_of_all_triage_team_recipients') do
            get '/mobile/v0/messaging/health/allrecipients', headers: sis_headers
          end
          expect(response).to be_successful
          SchemaContract::ValidationJob.drain
          expect(SchemaContract::Validation.last.status).to eq('success')
        end
      end
    end
  end
end
