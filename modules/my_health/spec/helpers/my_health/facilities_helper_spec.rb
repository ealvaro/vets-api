# frozen_string_literal: true

require 'rails_helper'
require 'vets/collection'

RSpec.describe MyHealth::FacilitiesHelper do
  def build_collection(teams_data)
    teams = teams_data.map { |data| AllTriageTeams.new(data) }
    Vets::Collection.new(teams, AllTriageTeams)
  end

  describe '.set_health_care_system_names' do
    context 'with COMPLICATED_SYSTEMS stations' do
      it 'overrides health_care_system_name for all COMPLICATED_SYSTEMS stations' do
        teams_data = described_class::COMPLICATED_SYSTEMS.keys.map.with_index do |station, i|
          { triage_team_id: i + 1, name: "Team #{i}", station_number: station,
            health_care_system_name: 'API Provided Name' }
        end
        collection = build_collection(teams_data)

        described_class.set_health_care_system_names(collection)

        collection.records.each do |team|
          expected = described_class::COMPLICATED_SYSTEMS[team.station_number]
          expect(team.health_care_system_name).to eq(expected)
        end
      end
    end

    context 'with non-prod station numbers' do
      before do
        allow(Settings).to receive(:hostname).and_return('staging-api.va.gov')
      end

      it 'converts station 979 to 552 and applies non-prod name override' do
        collection = build_collection([
                                        { triage_team_id: 1, name: 'Team A', station_number: '979' }
                                      ])

        described_class.set_health_care_system_names(collection)

        team = collection.records.first
        expect(team.station_number).to eq('552')
        expect(team.health_care_system_name).to eq('VA Dayton health care')
      end

      it 'converts station 989 to 442 and applies non-prod name override' do
        collection = build_collection([
                                        { triage_team_id: 1, name: 'Team A', station_number: '989' }
                                      ])

        described_class.set_health_care_system_names(collection)

        team = collection.records.first
        expect(team.station_number).to eq('442')
        expect(team.health_care_system_name).to eq('VA Cheyenne health care')
      end

      it 'applies non-prod override even when API provides a health_care_system_name' do
        collection = build_collection([
                                        { triage_team_id: 1, name: 'Team A', station_number: '979',
                                          health_care_system_name: 'API Name' }
                                      ])

        described_class.set_health_care_system_names(collection)

        team = collection.records.first
        expect(team.health_care_system_name).to eq('VA Dayton health care')
      end
    end

    context 'with prod station numbers' do
      before do
        allow(Settings).to receive(:hostname).and_return('api.va.gov')
      end

      it 'does not convert station 979 in prod' do
        collection = build_collection([
                                        { triage_team_id: 1, name: 'Team A', station_number: '979',
                                          health_care_system_name: 'Some Name' }
                                      ])

        described_class.set_health_care_system_names(collection)

        team = collection.records.first
        expect(team.station_number).to eq('979')
        expect(team.health_care_system_name).to eq('Some Name')
      end

      it 'does not apply non-prod name override for native 552 in prod' do
        collection = build_collection([
                                        { triage_team_id: 1, name: 'Team A', station_number: '552',
                                          health_care_system_name: 'VA Dayton Medical Center' }
                                      ])

        described_class.set_health_care_system_names(collection)

        team = collection.records.first
        expect(team.station_number).to eq('552')
        expect(team.health_care_system_name).to eq('VA Dayton Medical Center')
      end

      it 'converts station 612 to 612A4 and applies COMPLICATED_SYSTEMS override' do
        collection = build_collection([
                                        { triage_team_id: 1, name: 'Team A', station_number: '612',
                                          health_care_system_name: 'API Name' }
                                      ])

        described_class.set_health_care_system_names(collection)

        team = collection.records.first
        expect(team.station_number).to eq('612A4')
        expect(team.health_care_system_name).to eq('VA Northern California Healthcare (multiple facilities)')
      end
    end

    context 'with regular stations' do
      it 'preserves API-provided health_care_system_name' do
        collection = build_collection([
                                        { triage_team_id: 1, name: 'Team A', station_number: '520',
                                          health_care_system_name: 'VA Gulf Coast health care' }
                                      ])

        described_class.set_health_care_system_names(collection)

        team = collection.records.first
        expect(team.station_number).to eq('520')
        expect(team.health_care_system_name).to eq('VA Gulf Coast health care')
      end

      it 'falls back to station_number when health_care_system_name is nil' do
        collection = build_collection([
                                        { triage_team_id: 1, name: 'Team A', station_number: '520' }
                                      ])

        described_class.set_health_care_system_names(collection)

        team = collection.records.first
        expect(team.health_care_system_name).to eq('520')
      end
    end

    it 'returns the collection' do
      collection = build_collection([
                                      { triage_team_id: 1, name: 'Team A', station_number: '520',
                                        health_care_system_name: 'Name' }
                                    ])

      result = described_class.set_health_care_system_names(collection)
      expect(result).to eq(collection)
    end
  end

  describe '.convert_non_prod_id' do
    context 'in non-prod' do
      before { allow(Settings).to receive(:hostname).and_return('staging-api.va.gov') }

      it 'converts 979 to 552' do
        expect(described_class.convert_non_prod_id('979')).to eq('552')
      end

      it 'converts 989 to 442' do
        expect(described_class.convert_non_prod_id('989')).to eq('442')
      end

      it 'returns other IDs unchanged' do
        expect(described_class.convert_non_prod_id('528')).to eq('528')
      end
    end

    context 'in prod' do
      before { allow(Settings).to receive(:hostname).and_return('api.va.gov') }

      it 'returns 979 unchanged' do
        expect(described_class.convert_non_prod_id('979')).to eq('979')
      end

      it 'returns 989 unchanged' do
        expect(described_class.convert_non_prod_id('989')).to eq('989')
      end
    end
  end

  describe '.convert_prod_id' do
    it 'converts 612 to 612A4' do
      expect(described_class.convert_prod_id('612')).to eq('612A4')
    end

    it 'returns other IDs unchanged' do
      expect(described_class.convert_prod_id('528')).to eq('528')
    end
  end

  describe '.convert_non_prod_ids' do
    context 'in non-prod' do
      before { allow(Settings).to receive(:hostname).and_return('staging-api.va.gov') }

      it 'converts all non-prod IDs in the array' do
        result = described_class.convert_non_prod_ids(%w[979 989 528])
        expect(result).to eq(%w[552 442 528])
      end
    end

    context 'in prod' do
      before { allow(Settings).to receive(:hostname).and_return('api.va.gov') }

      it 'returns the array unchanged' do
        ids = %w[979 989 528]
        expect(described_class.convert_non_prod_ids(ids)).to eq(ids)
      end
    end
  end
end
