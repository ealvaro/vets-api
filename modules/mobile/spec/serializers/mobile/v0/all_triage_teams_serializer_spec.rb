# frozen_string_literal: true

require 'rails_helper'

describe Mobile::V0::AllTriageTeamsSerializer, type: :serializer do
  subject { serialize(all_triage_team, serializer_class: described_class) }

  let(:all_triage_team) do
    AllTriageTeams.new(
      triage_team_id: 123,
      name: 'Primary Care Team',
      station_number: '989',
      preferred_team: false,
      relation_type: 'PATIENT',
      location_name: 'Main Hospital',
      suggested_name_display: 'Primary Care',
      health_care_system_name: 'VA Health System',
      oh_triage_group: false,
      migrating_to_oh: false
    )
  end
  let(:data) { JSON.parse(subject)['data'] }
  let(:attributes) { data['attributes'] }

  it 'includes :id' do
    expect(data['id']).to eq '123'
  end

  it 'includes :triage_team_id' do
    expect(attributes['triage_team_id']).to eq 123
  end

  it 'includes :name' do
    expect(attributes['name']).to eq 'Primary Care'
  end

  it 'includes :station_number' do
    expect(attributes['station_number']).to eq '989'
  end

  it 'includes :preferred_team' do
    expect(attributes['preferred_team']).to be false
  end

  it 'includes :relation_type' do
    expect(attributes['relation_type']).to eq 'PATIENT'
  end

  it 'includes :location_name' do
    expect(attributes['location_name']).to eq 'Main Hospital'
  end

  it 'includes :suggested_name_display' do
    expect(attributes['suggested_name_display']).to eq 'Primary Care'
  end

  it 'includes :health_care_system_name' do
    expect(attributes['health_care_system_name']).to eq 'VA Health System'
  end

  it 'includes :oh_triage_group' do
    expect(attributes['oh_triage_group']).to be false
  end

  it 'includes :migrating_to_oh' do
    expect(attributes['migrating_to_oh']).to be false
  end

  it 'includes :signature_required' do
    expect(attributes['signature_required']).to be false
  end

  context 'when suggested_name_display is blank' do
    let(:all_triage_team) do
      AllTriageTeams.new(
        triage_team_id: 456,
        name: 'Fallback Team Name',
        suggested_name_display: nil
      )
    end

    it 'falls back to name for :name attribute' do
      expect(attributes['name']).to eq 'Fallback Team Name'
    end
  end
end
