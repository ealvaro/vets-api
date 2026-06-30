# frozen_string_literal: true

require 'rails_helper'
require 'sm/client'

describe 'sm client' do
  describe 'triage_teams' do
    subject(:client) { @client }

    before do
      VCR.use_cassette 'sm_client/session' do
        @client ||= begin
          client = SM::Client.new(session: { user_id: '10616687' })
          client.authenticate
          client
        end
      end
    end

    it 'gets a collection of triage team recipients', :vcr do
      folders = client.get_triage_teams('1234', false)
      expect(folders).to be_a(Vets::Collection)
      expect(folders.type).to eq(TriageTeam)
    end

    it 'populates health care system names' do
      VCR.use_cassette 'sm_client/triage_teams/gets_a_collection_of_all_triage_team_recipients' do
        VCR.use_cassette('sm_client/get_unique_care_systems') do
          all_triage_teams = client.get_all_triage_teams('1234')
          all_triage_teams.records.each { |record| expect(record.health_care_system_name).not_to be_nil }
        end
      end
    end

    it 'does not cache triage teams' do
      VCR.use_cassette 'sm_client/triage_teams/gets_a_collection_of_triage_team_recipients' do
        client.get_triage_teams('1234', false)
        expect(TriageTeam.get_cached('1234-triage-teams')).to be_nil
      end
    end

    it 'does not cache all triage teams' do
      VCR.use_cassette 'sm_client/triage_teams/gets_a_collection_of_all_triage_team_recipients' do
        VCR.use_cassette('sm_client/get_unique_care_systems') do
          client.get_all_triage_teams('1234')
          expect(AllTriageTeams.get_cached('1234-all-triage-teams')).to be_nil
        end
      end
    end

    it 'caches triage_team_id and station_number via TriageTeamCache' do
      VCR.use_cassette 'sm_client/triage_teams/gets_a_collection_of_all_triage_team_recipients' do
        VCR.use_cassette('sm_client/get_unique_care_systems') do
          client.get_all_triage_teams('1234')

          cached_data = TriageTeamCache.get_cached('1234-all-triage-teams-station-numbers')
          expect(cached_data).not_to be_nil
          expect(cached_data).to be_an(Array)
          expect(cached_data.first).to respond_to(:triage_team_id)
          expect(cached_data.first).to respond_to(:station_number)
        end
      end
    end

    it 'caches only minimal triage team data with correct attributes' do
      VCR.use_cassette 'sm_client/triage_teams/gets_a_collection_of_all_triage_team_recipients' do
        VCR.use_cassette('sm_client/get_unique_care_systems') do
          collection = client.get_all_triage_teams('user-uuid-123')

          cached_data = TriageTeamCache.get_cached('user-uuid-123-all-triage-teams-station-numbers')
          expect(cached_data.length).to eq(collection.data.length)

          # Verify cached data matches the original collection's triage_team_id and station_number
          collection.data.each_with_index do |team, index|
            expect(cached_data[index].triage_team_id).to eq(team.triage_team_id)
            expect(cached_data[index].station_number).to eq(team.station_number)
          end
        end
      end
    end

    it 'includes metadata counts that match collection data' do
      VCR.use_cassette 'sm_client/triage_teams/gets_a_collection_of_all_triage_team_recipients' do
        VCR.use_cassette('sm_client/get_unique_care_systems') do
          collection = client.get_all_triage_teams('1234')

          # Verify metadata keys exist and have correct types
          expect(collection.metadata).to have_key(:associated_triage_groups)
          expect(collection.metadata).to have_key(:associated_blocked_triage_groups)
          expect(collection.metadata[:associated_triage_groups]).to be_an(Integer)
          expect(collection.metadata[:associated_blocked_triage_groups]).to be_an(Integer)

          # Verify associated_triage_groups matches collection data length
          expect(collection.metadata[:associated_triage_groups]).to eq(collection.data.length)

          # When no teams are migrating or blocked, count should be 0
          expect(collection.metadata[:associated_blocked_triage_groups]).to eq(0)
        end
      end
    end

    describe 'healthCareSystemName logging' do
      it 'logs unique healthCareSystemName values' do
        allow(Rails.logger).to receive(:info)

        VCR.use_cassette 'sm_client/triage_teams/gets_a_collection_of_all_triage_team_recipients' do
          VCR.use_cassette('sm_client/get_unique_care_systems') do
            client.get_all_triage_teams('1234')
          end
        end

        expect(Rails.logger).to have_received(:info).with(
          'AllTriageTeams healthCareSystemName validation',
          hash_including(:health_care_system_names)
        ).once
      end

      it 'logs warn with team names when healthCareSystemName values are blank' do
        allow(Rails.logger).to receive(:info)
        allow(Rails.logger).to receive(:warn)
        allow(MHV::OhFacilitiesHelper::Service).to receive(:new)
          .and_return(instance_double(MHV::OhFacilitiesHelper::Service, get_phases_for_station_numbers: {}))

        VCR.use_cassette 'sm_client/triage_teams/gets_all_triage_team_recipients_with_some_blank_system_names' do
          VCR.use_cassette('sm_client/get_unique_care_systems') do
            client.get_all_triage_teams('1234')
          end
        end

        expect(Rails.logger).to have_received(:info).with(
          'AllTriageTeams healthCareSystemName validation',
          hash_including(:health_care_system_names)
        ).once

        expect(Rails.logger).to have_received(:warn).with(
          'AllTriageTeams missing healthCareSystemName',
          hash_including(triage_team_names: array_including('Team C'))
        ).once
      end

      it 'does not log warn when all healthCareSystemName values are present' do
        allow(Rails.logger).to receive(:info)
        allow(Rails.logger).to receive(:warn)
        allow(MHV::OhFacilitiesHelper::Service).to receive(:new)
          .and_return(instance_double(MHV::OhFacilitiesHelper::Service, get_phases_for_station_numbers: {}))

        VCR.use_cassette 'sm_client/triage_teams/gets_a_collection_of_all_triage_team_recipients' do
          VCR.use_cassette('sm_client/get_unique_care_systems') do
            client.get_all_triage_teams('1234')
          end
        end

        expect(Rails.logger).not_to have_received(:warn)
      end
    end

    describe '#get_triage_teams_station_numbers' do
      it 'returns cached triage team station numbers when cache exists' do
        # Pre-populate the cache
        cache_key = "#{client.session.user_uuid}-all-triage-teams-station-numbers"
        cached_data = [
          { triage_team_id: 123, station_number: '456' },
          { triage_team_id: 789, station_number: '012' }
        ]
        TriageTeamCache.set_cached(cache_key, cached_data)

        result = client.get_triage_teams_station_numbers

        expect(result).to be_an(Array)
        expect(result.length).to eq(2)
        expect(result.first.triage_team_id).to eq(123)
        expect(result.first.station_number).to eq('456')
        expect(result.last.triage_team_id).to eq(789)
        expect(result.last.station_number).to eq('012')
      end

      it 'fetches and caches data when cache is empty' do
        VCR.use_cassette 'sm_client/triage_teams/gets_a_collection_of_all_triage_team_recipients' do
          VCR.use_cassette('sm_client/get_unique_care_systems') do
            result = client.get_triage_teams_station_numbers

            expect(result).to be_an(Array)
            expect(result).not_to be_empty
            expect(result.first).to respond_to(:triage_team_id)
            expect(result.first).to respond_to(:station_number)
          end
        end
      end

      it 'returns empty array when API returns no data' do
        VCR.use_cassette 'sm_client/triage_teams/gets_empty_all_triage_team_recipients' do
          VCR.use_cassette('sm_client/get_unique_care_systems') do
            result = client.get_triage_teams_station_numbers

            # When cache is empty and API returns empty, result is an empty array
            expect(result).to be_an(Array)
            expect(result).to be_empty
          end
        end
      end
    end

    describe 'station number and health care system name processing' do
      it 'converts non-prod station numbers' do
        VCR.use_cassette 'sm_client/triage_teams/gets_a_collection_of_all_triage_team_recipients' do
          VCR.use_cassette('sm_client/get_unique_care_systems') do
            collection = client.get_all_triage_teams('1234')

            # VCR cassette has station 979, which should be converted to 552 in non-prod
            team = collection.data.find { |t| t.triage_team_id == 4_399_547 }
            expect(team.station_number).to eq('552')
          end
        end
      end

      it 'converts prod station number 612 to 612A4' do
        cassette = 'sm_client/triage_teams/gets_a_collection_of_all_triage_team_recipients_include_complex_teams'
        VCR.use_cassette(cassette) do
          collection = client.get_all_triage_teams('1234')

          team = collection.data.find { |t| t.triage_team_id == 4_399_554 }
          expect(team.station_number).to eq('612A4')
        end
      end

      it 'overrides health_care_system_name for COMPLICATED_SYSTEMS stations' do
        cassette = 'sm_client/triage_teams/gets_a_collection_of_all_triage_team_recipients_include_complex_teams'
        VCR.use_cassette(cassette) do
          collection = client.get_all_triage_teams('1234')

          expected_overrides = {
            '528' => 'VA New York State Healthcare (multiple facilities)',
            '589' => 'VA Kansas and Missouri Healthcare (multiple facilities)',
            '620' => 'VA Hudson Valley New York Healthcare (multiple facilities)',
            '626' => 'VA Tennessee Healthcare (multiple facilities)',
            '636' => 'VA Nebraska and Iowa Healthcare (multiple facilities)',
            '657' => 'VA Missouri and Illinois Healthcare (multiple facilities)',
            '612A4' => 'VA Northern California Healthcare (multiple facilities)'
          }

          expected_overrides.each do |station, expected_name|
            team = collection.data.find { |t| t.station_number == station }
            msg = "expected station #{station} name '#{expected_name}', got '#{team.health_care_system_name}'"
            expect(team.health_care_system_name).to eq(expected_name), msg
          end
        end
      end

      it 'applies non-prod system name override for converted station numbers' do
        VCR.use_cassette 'sm_client/triage_teams/gets_a_collection_of_all_triage_team_recipients' do
          VCR.use_cassette('sm_client/get_unique_care_systems') do
            collection = client.get_all_triage_teams('1234')

            # Station 979 → 552 gets NON_PROD_SYSTEM_NAMES override
            team = collection.data.find { |t| t.triage_team_id == 4_399_547 }
            expect(team.health_care_system_name).to eq('VA Dayton health care')
          end
        end
      end

      it 'caches converted station numbers' do
        VCR.use_cassette 'sm_client/triage_teams/gets_a_collection_of_all_triage_team_recipients' do
          VCR.use_cassette('sm_client/get_unique_care_systems') do
            client.get_all_triage_teams('1234')

            cached_data = TriageTeamCache.get_cached('1234-all-triage-teams-station-numbers')
            cached_team = cached_data.find { |t| t.triage_team_id == 4_399_547 }
            expect(cached_team.station_number).to eq('552')
          end
        end
      end
    end

    describe 'OH migration status check' do
      let(:oh_service) { instance_double(MHV::OhFacilitiesHelper::Service) }

      before do
        allow(MHV::OhFacilitiesHelper::Service).to receive(:new).and_return(oh_service)
      end

      it 'excludes teams when station is in p3 phase' do
        allow(oh_service).to receive(:get_phases_for_station_numbers).and_return({ '979' => 'p3' })

        VCR.use_cassette 'sm_client/triage_teams/gets_a_collection_of_all_triage_team_recipients' do
          VCR.use_cassette('sm_client/get_unique_care_systems') do
            collection = client.get_all_triage_teams('1234')

            # Teams with station 979 should be excluded
            expect(collection.data).to be_empty

            # Verify metadata reflects the empty collection
            expect(collection.metadata[:associated_triage_groups]).to eq(0)
            expect(collection.metadata[:associated_triage_groups]).to eq(collection.data.length)
            expect(collection.metadata[:associated_blocked_triage_groups]).to eq(0)
          end
        end
      end

      it 'excludes teams when station is in p4 phase' do
        allow(oh_service).to receive(:get_phases_for_station_numbers).and_return({ '979' => 'p4' })

        VCR.use_cassette 'sm_client/triage_teams/gets_a_collection_of_all_triage_team_recipients' do
          VCR.use_cassette('sm_client/get_unique_care_systems') do
            collection = client.get_all_triage_teams('1234')

            # Teams with station 979 should be excluded
            expect(collection.data).to be_empty
            expect(collection.metadata[:associated_triage_groups]).to eq(collection.data.length)
            expect(collection.metadata[:associated_blocked_triage_groups]).to eq(0)
          end
        end
      end

      it 'excludes teams when station is in p5 phase' do
        allow(oh_service).to receive(:get_phases_for_station_numbers).and_return({ '979' => 'p5' })

        VCR.use_cassette 'sm_client/triage_teams/gets_a_collection_of_all_triage_team_recipients' do
          VCR.use_cassette('sm_client/get_unique_care_systems') do
            collection = client.get_all_triage_teams('1234')

            # Teams with station 979 should be excluded
            expect(collection.data).to be_empty
            expect(collection.metadata[:associated_triage_groups]).to eq(collection.data.length)
            expect(collection.metadata[:associated_blocked_triage_groups]).to eq(0)
          end
        end
      end

      it 'includes teams when phase is nil' do
        allow(oh_service).to receive(:get_phases_for_station_numbers).and_return({})

        VCR.use_cassette 'sm_client/triage_teams/gets_a_collection_of_all_triage_team_recipients' do
          VCR.use_cassette('sm_client/get_unique_care_systems') do
            collection = client.get_all_triage_teams('1234')

            # Teams should not be excluded when phase is nil
            expect(collection.data).not_to be_empty

            # Verify metadata matches collection
            expect(collection.metadata[:associated_triage_groups]).to eq(collection.data.length)
            expect(collection.metadata[:associated_blocked_triage_groups]).to eq(0)
          end
        end
      end

      it 'includes teams when station is in p2 phase' do
        allow(oh_service).to receive(:get_phases_for_station_numbers).and_return({ '979' => 'p2' })

        VCR.use_cassette 'sm_client/triage_teams/gets_a_collection_of_all_triage_team_recipients' do
          VCR.use_cassette('sm_client/get_unique_care_systems') do
            collection = client.get_all_triage_teams('1234')

            # Teams should not be excluded in p2 phase
            expect(collection.data).not_to be_empty
            expect(collection.metadata[:associated_triage_groups]).to eq(collection.data.length)
            expect(collection.metadata[:associated_blocked_triage_groups]).to eq(0)
          end
        end
      end

      it 'includes teams when station is in p6 phase' do
        allow(oh_service).to receive(:get_phases_for_station_numbers).and_return({ '979' => 'p6' })

        VCR.use_cassette 'sm_client/triage_teams/gets_a_collection_of_all_triage_team_recipients' do
          VCR.use_cassette('sm_client/get_unique_care_systems') do
            collection = client.get_all_triage_teams('1234')

            # Teams should not be excluded in p6 phase
            expect(collection.data).not_to be_empty
            expect(collection.metadata[:associated_triage_groups]).to eq(collection.data.length)
            expect(collection.metadata[:associated_blocked_triage_groups]).to eq(0)
          end
        end
      end

      it 'includes teams when station is in p7 phase' do
        allow(oh_service).to receive(:get_phases_for_station_numbers).and_return({ '979' => 'p7' })

        VCR.use_cassette 'sm_client/triage_teams/gets_a_collection_of_all_triage_team_recipients' do
          VCR.use_cassette('sm_client/get_unique_care_systems') do
            collection = client.get_all_triage_teams('1234')

            # Teams should not be excluded in p7 phase
            expect(collection.data).not_to be_empty
            expect(collection.metadata[:associated_triage_groups]).to eq(collection.data.length)
            expect(collection.metadata[:associated_blocked_triage_groups]).to eq(0)
          end
        end
      end
    end

    describe 'virtual triage group (VTG) filtering' do
      let(:oh_service) { instance_double(MHV::OhFacilitiesHelper::Service) }

      before do
        allow(MHV::OhFacilitiesHelper::Service).to receive(:new).and_return(oh_service)
        allow(oh_service).to receive(:get_phases_for_station_numbers).and_return({})
      end

      it 'parses virtual_group attribute from API response' do
        VCR.use_cassette 'sm_client/triage_teams/gets_all_triage_teams_with_virtual_groups' do
          collection = client.get_all_triage_teams('1234', filter_non_pretransitioned_vtgs: false)

          vtg_teams = collection.data.select(&:virtual_group)
          non_vtg_teams = collection.data.reject(&:virtual_group)

          expect(vtg_teams).not_to be_empty
          expect(non_vtg_teams).not_to be_empty

          # Verify known VTG teams have virtual_group = true
          known_vtg = collection.data.find { |t| t.triage_team_id == 6_725_162 }
          expect(known_vtg).to be_present
          expect(known_vtg.virtual_group).to be true
          expect(known_vtg.station_number).to eq('668')

          # Verify known non-VTG teams have virtual_group = false
          known_non_vtg = collection.data.find { |t| t.triage_team_id == 6_238_822 }
          expect(known_non_vtg).to be_present
          expect(known_non_vtg.virtual_group).to be false
        end
      end

      context 'when filter_non_pretransitioned_vtgs is true (default)' do
        it 'removes VTGs at non-pretransitioned stations' do
          # Test settings: pretransitioned_oh_facilities = 612, 357, 555
          # Cassette has stations 668 and 757 — neither is pretransitioned
          VCR.use_cassette 'sm_client/triage_teams/gets_all_triage_teams_with_virtual_groups' do
            collection = client.get_all_triage_teams('1234', filter_non_pretransitioned_vtgs: true)

            vtg_teams = collection.data.select(&:virtual_group)
            expect(vtg_teams).to be_empty

            # Known VTG IDs from the cassette should not be present
            team_ids = collection.data.map(&:triage_team_id)
            expect(team_ids).not_to include(6_725_162) # SM668 CANCER CARE (VTG at 668)
            expect(team_ids).not_to include(6_692_633) # Columbus VTG at 757
          end
        end

        it 'keeps non-VTG teams regardless of station' do
          VCR.use_cassette 'sm_client/triage_teams/gets_all_triage_teams_with_virtual_groups' do
            collection = client.get_all_triage_teams('1234', filter_non_pretransitioned_vtgs: true)

            non_vtg_teams = collection.data.reject(&:virtual_group)
            expect(non_vtg_teams).not_to be_empty

            # Known non-VTG IDs should still be present
            team_ids = collection.data.map(&:triage_team_id)
            expect(team_ids).to include(6_238_822) # VHA SPO ALS (non-VTG at 668)
            expect(team_ids).to include(6_238_639) # VHA COS Allergy (non-VTG at 757)

            # All remaining teams should have virtual_group = false
            expect(collection.data).to all(have_attributes(virtual_group: false))

            # Both stations' non-VTG teams should be present
            stations = collection.data.map(&:station_number).uniq.sort
            expect(stations).to eq(%w[668 757])
          end
        end

        it 'keeps VTGs at pretransitioned stations' do
          # Add station 668 to pretransitioned list so its VTGs are kept
          allow(Settings.mhv.oh_facility_checks).to receive(:pretransitioned_oh_facilities)
            .and_return('612, 357, 555, 668')

          VCR.use_cassette 'sm_client/triage_teams/gets_all_triage_teams_with_virtual_groups' do
            collection = client.get_all_triage_teams('1234', filter_non_pretransitioned_vtgs: true)

            vtg_at_station668 = collection.data.select { |t| t.virtual_group && t.station_number == '668' }
            vtg_at_station757 = collection.data.select { |t| t.virtual_group && t.station_number == '757' }

            # 668 is pretransitioned — its VTGs should be kept
            expect(vtg_at_station668).not_to be_empty
            expect(vtg_at_station668.map(&:triage_team_id)).to include(6_725_162) # SM668 CANCER CARE

            # 757 is NOT pretransitioned — its VTGs should be filtered out
            expect(vtg_at_station757).to be_empty
            team_ids = collection.data.map(&:triage_team_id)
            expect(team_ids).not_to include(6_692_633) # Columbus VTG at 757

            # Non-VTG teams at both stations should still be present
            non_vtg_stations = collection.data.reject(&:virtual_group).map(&:station_number).uniq.sort
            expect(non_vtg_stations).to eq(%w[668 757])
          end
        end

        it 'updates metadata counts to reflect filtered results' do
          VCR.use_cassette 'sm_client/triage_teams/gets_all_triage_teams_with_virtual_groups' do
            collection = client.get_all_triage_teams('1234', filter_non_pretransitioned_vtgs: true)

            # Metadata should match actual collection size
            expect(collection.metadata[:associated_triage_groups]).to eq(collection.data.length)

            # No VTGs should remain — only non-VTG teams
            expect(collection.data).to all(have_attributes(virtual_group: false))
          end
        end
      end

      context 'when using defaults (filter_non_pretransitioned_vtgs: true, filter_pretransitioned_vtgs: false)' do
        it 'filters non-pretransitioned VTGs by default when kwargs are not passed' do
          VCR.use_cassette 'sm_client/triage_teams/gets_all_triage_teams_with_virtual_groups' do
            collection = client.get_all_triage_teams('1234')

            # Default is filter_non_pretransitioned_vtgs: true — non-pretransitioned VTGs should be filtered
            team_ids = collection.data.map(&:triage_team_id)
            expect(team_ids).not_to include(6_725_162) # SM668 CANCER CARE (VTG at 668)
            expect(team_ids).not_to include(6_692_633) # Columbus VTG at 757

            # Non-VTG teams should still be present
            expect(team_ids).to include(6_238_822) # VHA SPO ALS (non-VTG at 668)
            expect(collection.data).to all(have_attributes(virtual_group: false))
          end
        end
      end

      context 'when filter_non_pretransitioned_vtgs is explicitly false' do
        it 'returns all teams including VTGs at non-pretransitioned stations' do
          VCR.use_cassette 'sm_client/triage_teams/gets_all_triage_teams_with_virtual_groups' do
            collection = client.get_all_triage_teams('1234', filter_non_pretransitioned_vtgs: false)

            team_ids = collection.data.map(&:triage_team_id)
            expect(team_ids).to include(6_725_162) # VTG should still be present
            expect(team_ids).to include(6_692_633) # Columbus VTG at 757
            expect(team_ids).to include(6_238_822) # non-VTG should still be present
          end
        end
      end

      context 'when filter_pretransitioned_vtgs is true' do
        it 'removes VTGs at pretransitioned stations' do
          # Add station 668 to pretransitioned list
          allow(Settings.mhv.oh_facility_checks).to receive(:pretransitioned_oh_facilities)
            .and_return('612, 357, 555, 668')

          VCR.use_cassette 'sm_client/triage_teams/gets_all_triage_teams_with_virtual_groups' do
            collection = client.get_all_triage_teams('1234', filter_non_pretransitioned_vtgs: false,
                                                             filter_pretransitioned_vtgs: true)

            # VTG at pretransitioned station 668 should be removed
            team_ids = collection.data.map(&:triage_team_id)
            expect(team_ids).not_to include(6_725_162) # SM668 CANCER CARE (VTG at 668, pretransitioned)

            # VTG at non-pretransitioned station 757 should be kept (filter_non_pretransitioned is false)
            expect(team_ids).to include(6_692_633) # Columbus VTG at 757

            # Non-VTG teams should still be present at both stations
            expect(team_ids).to include(6_238_822) # VHA SPO ALS (non-VTG at 668)
            expect(team_ids).to include(6_238_639) # VHA COS Allergy (non-VTG at 757)
          end
        end

        it 'keeps non-VTG teams at pretransitioned stations' do
          allow(Settings.mhv.oh_facility_checks).to receive(:pretransitioned_oh_facilities)
            .and_return('612, 357, 555, 668')

          VCR.use_cassette 'sm_client/triage_teams/gets_all_triage_teams_with_virtual_groups' do
            collection = client.get_all_triage_teams('1234', filter_non_pretransitioned_vtgs: false,
                                                             filter_pretransitioned_vtgs: true)

            non_vtg_at_station = collection.data.select { |t| !t.virtual_group && t.station_number == '668' }
            expect(non_vtg_at_station).not_to be_empty
          end
        end
      end

      context 'when both filters are true' do
        it 'removes ALL VTGs regardless of station' do
          # Add station 668 to pretransitioned list
          allow(Settings.mhv.oh_facility_checks).to receive(:pretransitioned_oh_facilities)
            .and_return('612, 357, 555, 668')

          VCR.use_cassette 'sm_client/triage_teams/gets_all_triage_teams_with_virtual_groups' do
            collection = client.get_all_triage_teams('1234', filter_non_pretransitioned_vtgs: true,
                                                             filter_pretransitioned_vtgs: true)

            # ALL VTGs should be removed
            vtg_teams = collection.data.select(&:virtual_group)
            expect(vtg_teams).to be_empty

            team_ids = collection.data.map(&:triage_team_id)
            expect(team_ids).not_to include(6_725_162) # SM668 CANCER CARE (VTG at 668, pretransitioned)
            expect(team_ids).not_to include(6_692_633) # Columbus VTG at 757
          end
        end

        it 'keeps non-VTG teams regardless of station' do
          VCR.use_cassette 'sm_client/triage_teams/gets_all_triage_teams_with_virtual_groups' do
            collection = client.get_all_triage_teams('1234', filter_non_pretransitioned_vtgs: true,
                                                             filter_pretransitioned_vtgs: true)

            non_vtg_teams = collection.data.reject(&:virtual_group)
            expect(non_vtg_teams).not_to be_empty

            team_ids = collection.data.map(&:triage_team_id)
            expect(team_ids).to include(6_238_822) # VHA SPO ALS (non-VTG at 668)
            expect(team_ids).to include(6_238_639) # VHA COS Allergy (non-VTG at 757)

            expect(collection.data).to all(have_attributes(virtual_group: false))
          end
        end

        it 'updates metadata counts to reflect all VTGs removed' do
          allow(Settings.mhv.oh_facility_checks).to receive(:pretransitioned_oh_facilities)
            .and_return('612, 357, 555, 668')

          VCR.use_cassette 'sm_client/triage_teams/gets_all_triage_teams_with_virtual_groups' do
            collection = client.get_all_triage_teams('1234', filter_non_pretransitioned_vtgs: true,
                                                             filter_pretransitioned_vtgs: true)

            expect(collection.metadata[:associated_triage_groups]).to eq(collection.data.length)
            expect(collection.data).to all(have_attributes(virtual_group: false))
          end
        end
      end

      context 'when both filters are false' do
        it 'returns all teams including all VTGs' do
          VCR.use_cassette 'sm_client/triage_teams/gets_all_triage_teams_with_virtual_groups' do
            collection = client.get_all_triage_teams('1234', filter_non_pretransitioned_vtgs: false,
                                                             filter_pretransitioned_vtgs: false)

            team_ids = collection.data.map(&:triage_team_id)
            expect(team_ids).to include(6_725_162) # VTG should be present
            expect(team_ids).to include(6_692_633) # Columbus VTG at 757
            expect(team_ids).to include(6_238_822) # non-VTG should be present
          end
        end
      end
    end
  end
end
