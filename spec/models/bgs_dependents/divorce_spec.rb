# frozen_string_literal: true

require 'rails_helper'

RSpec.describe BGSDependents::Divorce do
  let(:divorce_info_v2) do
    {
      'date' => '2020-01-01',
      'ssn' => '848525794',
      'birth_date' => '1990-03-03',
      'full_name' => { 'first' => 'Billy', 'middle' => 'Yohan', 'last' => 'Johnson', 'suffix' => 'Sr.' },
      'divorce_location' => { 'location' => { 'state' => 'FL', 'city' => 'Tampa' } },
      'reason_marriage_ended' => 'Divorce'
    }
  end
  let(:formatted_params_result) do
    {
      'divorce_state' => 'FL',
      'divorce_city' => 'Tampa',
      'ssn' => '848525794',
      'birth_date' => '1990-03-03',
      'divorce_country' => nil,
      'marriage_termination_type_code' => 'Divorce',
      'end_date' => DateTime.parse("#{divorce_info_v2['date']} 12:00:00").to_time.iso8601,
      'vet_ind' => 'N',
      'type' => 'divorce',
      'first' => 'Billy',
      'middle' => 'Yohan',
      'last' => 'Johnson',
      'suffix' => 'Sr.'
    }
  end

  describe '#format_info' do
    it 'formats divorce params for submission' do
      formatted_info = described_class.new(divorce_info_v2).format_info

      expect(formatted_info).to eq(formatted_params_result)
    end
  end

  describe '#divorce_state' do
    context 'when divorce occurred in the US' do
      it 'returns the state where the divorce occurred' do
        divorce = described_class.new(divorce_info_v2)
        expect(divorce.divorce_state).to eq('FL')
      end
    end

    context 'when divorce occurred outside the US' do
      let(:divorce_info_outside_us) do
        divorce_info_v2.merge(
          'divorce_location' => {
            'outside_usa' => true,
            'location' => {
              'state' => 'NA',
              'city' => 'Toronto',
              'country' => 'Canada'
            }
          }
        )
      end

      it 'returns nil for the state' do
        divorce = described_class.new(divorce_info_outside_us)
        expect(divorce.divorce_state).to be_nil
      end
    end

    context 'when divorce location is missing' do
      let(:divorce_info_no_location) do
        divorce_info_v2.except('divorce_location')
      end

      it 'returns nil for the state' do
        divorce = described_class.new(divorce_info_no_location)
        expect(divorce.divorce_state).to be_nil
      end
    end
  end

  describe '#divorce_city' do
    context 'when city does not exceed limit' do
      it 'returns the city' do
        divorce = described_class.new(divorce_info_v2)
        expect(divorce.divorce_city).to eq('Tampa')
      end
    end

    context 'when divorce location is missing' do
      it 'returns nil for the city' do
        no_location = divorce_info_v2.except('divorce_location')
        divorce = described_class.new(no_location)
        expect(divorce.divorce_city).to be_nil
      end
    end

    context 'when city exceeds the limit' do
      it 'returns split value' do
        split = divorce_info_v2.merge(
          'divorce_location' => {
            'location' => {
              'state' => 'NA',
              'city' => 'Balneario Barra do Sul / Santa Catarina',
              'country' => 'Brazil'
            }
          }
        )

        divorce = described_class.new(split)
        expect(divorce.divorce_city).to eq('Balneario Barra do Sul')
      end

      it 'returns truncated value' do
        long = divorce_info_v2.merge(
          'divorce_location' => {
            'location' => {
              'state' => 'NA',
              'city' => 'Llanfairpwllgwyngyllgogerychwyrndrobwllllantysiliogogogoch / Wales', # this is a real place
              'country' => 'United Kingdom'
            }
          }
        )

        divorce = described_class.new(long)
        expect(divorce.divorce_city).to eq('Llanfairpwllgwyngyllgogerychwy')
      end
    end
  end

  describe '#marriage_termination_type_code' do
    context 'when reason_marriage_ended is an accepted value' do
      it 'returns the value' do
        divorce = described_class.new(divorce_info_v2)
        expect(divorce.marriage_termination_type_code).to eq('Divorce')
      end
    end

    context 'when reason_marriage_ended is NOT accepted' do
      it 'returns Other' do
        other = divorce_info_v2.merge({ 'reason_marriage_ended' => 'Annulment' })

        divorce = described_class.new(other)
        expect(divorce.marriage_termination_type_code).to eq('Other')
      end
    end
  end
end
