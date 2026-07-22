# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Mobile::V0::Adapters::AllergyIntolerance do
  subject(:adapter) { described_class.new }

  describe '#parse' do
    it 'uses recordedDate when both recordedDate and onsetDateTime are present' do
      allow(StatsD).to receive(:increment)

      parsed = adapter.parse([
                               {
                                 'resource' => {
                                   'id' => '1',
                                   'resourceType' => 'AllergyIntolerance',
                                   'type' => 'allergy',
                                   'clinicalStatus' => { 'coding' => [] },
                                   'code' => { 'coding' => [], 'text' => 'Latex allergy' },
                                   'recordedDate' => '2023-05-01T00:00:00+00:00',
                                   'onsetDateTime' => '2024-09-23T16:38:00+00:00',
                                   'patient' => {},
                                   'recorder' => {},
                                   'note' => [],
                                   'reaction' => [],
                                   'category' => ['environment']
                                 }
                               }
                             ])

      expect(parsed.first.recordedDate).to eq('2023-05-01T00:00:00+00:00')
      expect(StatsD).not_to have_received(:increment).with('mobile.allergy.replace_date_with_onset')
    end

    it 'uses onsetDateTime when recordedDate is blank' do
      parsed = adapter.parse([
                               {
                                 'resource' => {
                                   'id' => '1',
                                   'resourceType' => 'AllergyIntolerance',
                                   'type' => 'allergy',
                                   'clinicalStatus' => { 'coding' => [] },
                                   'code' => { 'coding' => [], 'text' => 'Latex allergy' },
                                   'recordedDate' => '',
                                   'onsetDateTime' => '2024-09-23T16:38:00+00:00',
                                   'patient' => {},
                                   'recorder' => {},
                                   'note' => [],
                                   'reaction' => [],
                                   'category' => ['environment']
                                 }
                               }
                             ])

      expect(parsed.length).to eq(1)
      expect(parsed.first.recordedDate).to eq('2024-09-23T16:38:00+00:00')
    end

    it 'sorts by fallback date when recordedDate is blank' do
      parsed = adapter.parse([
                               {
                                 'resource' => {
                                   'id' => 'older',
                                   'resourceType' => 'AllergyIntolerance',
                                   'type' => 'allergy',
                                   'clinicalStatus' => { 'coding' => [] },
                                   'code' => { 'coding' => [], 'text' => 'Older allergy' },
                                   'recordedDate' => nil,
                                   'onsetDateTime' => '2020-01-01T00:00:00+00:00',
                                   'patient' => {},
                                   'recorder' => {},
                                   'note' => [],
                                   'reaction' => [],
                                   'category' => ['environment']
                                 }
                               },
                               {
                                 'resource' => {
                                   'id' => 'newer',
                                   'resourceType' => 'AllergyIntolerance',
                                   'type' => 'allergy',
                                   'clinicalStatus' => { 'coding' => [] },
                                   'code' => { 'coding' => [], 'text' => 'Newer allergy' },
                                   'recordedDate' => nil,
                                   'onsetDateTime' => '2024-09-23T16:38:00+00:00',
                                   'patient' => {},
                                   'recorder' => {},
                                   'note' => [],
                                   'reaction' => [],
                                   'category' => ['environment']
                                 }
                               }
                             ])

      expect(parsed.map(&:id)).to eq(%w[older newer])
    end

    it 'does not increment the fallback metric or return an empty string when both dates are blank' do
      allow(StatsD).to receive(:increment)

      parsed = adapter.parse([
                               {
                                 'resource' => {
                                   'id' => '1',
                                   'resourceType' => 'AllergyIntolerance',
                                   'type' => 'allergy',
                                   'clinicalStatus' => { 'coding' => [] },
                                   'code' => { 'coding' => [], 'text' => 'Latex allergy' },
                                   'recordedDate' => '',
                                   'onsetDateTime' => '',
                                   'patient' => {},
                                   'recorder' => {},
                                   'note' => [],
                                   'reaction' => [],
                                   'category' => ['environment']
                                 }
                               }
                             ])

      expect(parsed.first.recordedDate).to be_nil
      expect(StatsD).not_to have_received(:increment).with('mobile.allergy.replace_date_with_onset')
    end
  end
end
