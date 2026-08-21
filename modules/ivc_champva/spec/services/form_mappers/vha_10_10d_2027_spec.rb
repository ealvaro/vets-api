# frozen_string_literal: true

require 'rails_helper'

RSpec.describe IvcChampva::FormMappers::VHA1010d2027 do
  let(:fixture_data) do
    JSON.parse(File.read('modules/ivc_champva/spec/fixtures/form_json/vha_10_10d.json'))
  end
  let(:form) { IvcChampva::VHA1010d2027.new(fixture_data) }
  let(:mapper) { described_class.new(form.data) }
  let(:fields) { mapper.mapped_fields }

  describe '#mapped_fields' do
    it 'returns a Hash' do
      expect(fields).to be_a(Hash)
    end

    context 'veteran fields' do
      it 'maps veteran name with suffix' do
        expect(fields['veteran_last_name']).to eq('Surname')
      end

      it 'maps veteran first name' do
        expect(fields['veteran_first_name']).to eq('Veteran')
      end

      it 'maps veteran middle initial' do
        expect(fields['veteran_middle_initial']).to eq('B')
      end

      it 'maps veteran SSN' do
        expect(fields['veteran_ssn']).to eq('222554444')
      end

      it 'maps veteran date of birth' do
        expect(fields['veteran_dob']).to eq('1987-02-02')
      end
    end

    context 'veteran radio buttons' do
      it 'returns 0 when sponsor is deceased' do
        expect(fields['sponsor_is_deceased_radio']).to eq(0)
      end

      it 'returns 0 when active service death is true' do
        expect(fields['is_active_service_death_radio']).to eq(0)
      end

      context 'when sponsor is not deceased' do
        let(:alive_data) do
          fixture_data.deep_dup.tap { |d| d['veteran']['sponsor_is_deceased'] = false }
        end
        let(:form) { IvcChampva::VHA1010d2027.new(alive_data) }

        it 'returns 1' do
          expect(fields['sponsor_is_deceased_radio']).to eq(1)
        end
      end
    end

    context 'applicant fields' do
      it 'maps applicant 1 name with suffix' do
        expect(fields['applicant_1_last_name']).to eq('Onceler')
      end

      it 'maps applicant 1 middle initial' do
        expect(fields['applicant_1_middle_initial']).to eq('C')
      end

      it 'maps applicant 1 gender radio' do
        expect(fields['applicant_1_gender_radio']).to be_nil
      end

      context 'with recognized gender values' do
        let(:male_data) do
          fixture_data.deep_dup.tap { |d| d['applicants'][0]['applicant_gender'] = 'male' }
        end
        let(:form) { IvcChampva::VHA1010d2027.new(male_data) }

        it 'returns 0 for male' do
          expect(fields['applicant_1_gender_radio']).to eq(0)
        end
      end

      it 'maps applicant 1 medicare radio (enrolled = 1)' do
        expect(fields['applicant_1_medicare_radio']).to eq(1)
      end

      it 'maps applicant 1 OHI radio (no = 0)' do
        expect(fields['applicant_1_ohi_radio']).to eq(0)
      end

      it 'maps applicant 2 OHI radio (yes = 1)' do
        expect(fields['applicant_2_ohi_radio']).to eq(1)
      end

      it 'maps applicant 1 relationship' do
        expect(fields['applicant_1_relationship']).to eq('spouse')
      end
    end

    context 'certification fields' do
      it 'maps certifier last name' do
        expect(fields['certifier_last_name']).to eq('Joe')
      end

      it 'maps certifier middle initial' do
        expect(fields['certifier_middle_initial']).to eq('C')
      end

      it 'maps statement of truth signature' do
        expect(fields['statement_of_truth_signature']).to eq('GI Joe')
      end
    end

    context 'when applicants array is empty' do
      let(:no_applicants_data) { fixture_data.deep_dup.tap { |d| d['applicants'] = [] } }
      let(:form) { IvcChampva::VHA1010d2027.new(no_applicants_data) }

      it 'returns nil for applicant fields' do
        expect(fields['applicant_1_first_name']).to be_nil
        expect(fields['applicant_2_first_name']).to be_nil
        expect(fields['applicant_3_first_name']).to be_nil
      end
    end
  end
end
