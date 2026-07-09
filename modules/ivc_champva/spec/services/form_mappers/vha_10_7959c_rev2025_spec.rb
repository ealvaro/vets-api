# frozen_string_literal: true

require 'rails_helper'

RSpec.describe IvcChampva::FormMappers::VHA107959cRev2025 do
  let(:fixture_data) do
    JSON.parse(File.read('modules/ivc_champva/spec/fixtures/form_json/vha_10_7959c_rev2025.json'))
  end
  let(:form) { IvcChampva::VHA107959cRev2025.new(fixture_data) }
  let(:mapper) { described_class.new(form.data) }
  let(:fields) { mapper.mapped_fields }

  describe '#mapped_fields' do
    it 'returns a Hash' do
      expect(fields).to be_a(Hash)
    end

    context 'name with suffix' do
      it 'returns last name without suffix when suffix is absent' do
        expect(fields['applicant_last_name']).to eq('Surname')
      end

      context 'when suffix is present' do
        let(:fixture_with_suffix) do
          fixture_data.deep_dup.tap do |d|
            d['applicants'].first['applicant_name']['suffix'] = 'Jr'
          end
        end
        let(:form) { IvcChampva::VHA107959cRev2025.new(fixture_with_suffix) }

        it 'appends suffix to last name' do
          expect(fields['applicant_last_name']).to eq('Surname Jr')
        end
      end
    end

    context 'new address radio' do
      it 'returns 0 when applicant_new_address is "no"' do
        expect(fields['new_address_radio']).to eq(0)
      end

      context 'when applicant_new_address is "yes"' do
        let(:fixture_with_new_address) do
          fixture_data.deep_dup.tap do |d|
            d['applicants'].first['applicant_new_address'] = 'yes'
          end
        end
        let(:form) { IvcChampva::VHA107959cRev2025.new(fixture_with_new_address) }

        it 'returns 1' do
          expect(fields['new_address_radio']).to eq(1)
        end
      end
    end

    context 'gender radio' do
      it 'returns 0 for male' do
        expect(fields['applicant_gender_radio']).to eq(0)
      end

      context 'when gender is a Hash' do
        let(:fixture_with_hash_gender) do
          fixture_data.deep_dup.tap do |d|
            d['applicants'].first['applicant_gender'] = { 'gender' => 'female' }
          end
        end
        let(:form) { IvcChampva::VHA107959cRev2025.new(fixture_with_hash_gender) }

        it 'returns 1 for female' do
          expect(fields['applicant_gender_radio']).to eq(1)
        end
      end
    end

    context 'medicare radios (plan_type c)' do
      it 'maps part A to 0' do
        expect(fields['medicare_part_a_radio']).to eq(0)
      end

      it 'maps part B to 0' do
        expect(fields['medicare_part_b_radio']).to eq(0)
      end

      it 'maps part C to 0' do
        expect(fields['medicare_part_c_radio']).to eq(0)
      end

      it 'maps part D to 0' do
        expect(fields['medicare_part_d_radio']).to eq(0)
      end

      context 'when medicare is blank' do
        let(:fixture_without_medicare) do
          fixture_data.deep_dup.tap do |d|
            d['applicants'].first.delete('medicare')
          end
        end
        let(:form) { IvcChampva::VHA107959cRev2025.new(fixture_without_medicare) }

        it 'returns nil for all medicare radios' do
          expect(fields['medicare_part_a_radio']).to be_nil
          expect(fields['medicare_part_b_radio']).to be_nil
          expect(fields['medicare_part_c_radio']).to be_nil
          expect(fields['medicare_part_d_radio']).to be_nil
        end
      end
    end

    context 'other insurance fields' do
      it 'maps has_other_insurance_radio to 1 when provider exists' do
        expect(fields['has_other_insurance_radio']).to eq(1)
      end

      it 'maps primary through employer radio to 0 for true' do
        expect(fields['primary_through_employer_radio']).to eq(0)
      end

      it 'maps primary EOB radio to 0 for true' do
        expect(fields['primary_eob_radio']).to eq(0)
      end

      it 'maps primary insurance type radios for medigap' do
        expect(fields['primary_insurance_hmo']).to eq('Off')
        expect(fields['primary_insurance_ppo']).to eq('Off')
        expect(fields['primary_insurance_medicaid']).to eq('Off')
        expect(fields['primary_insurance_medigap']).to eq(4)
        expect(fields['primary_insurance_other']).to eq('Off')
      end

      context 'when no primary provider' do
        let(:minimal_data) do
          {
            'applicant_name' => { 'first' => 'John', 'last' => 'Doe' },
            'applicant_ssn' => '123456789',
            'applicant_gender' => 'male',
            'form_number' => '10-7959C'
          }
        end
        let(:mapper) { described_class.new(minimal_data) }

        it 'returns 0 for has_other_insurance_radio' do
          expect(fields['has_other_insurance_radio']).to eq(0)
        end

        it 'returns nil for guarded employer radio' do
          expect(fields['primary_through_employer_radio']).to be_nil
        end
      end

      context 'when primary EOB is nil' do
        let(:data_with_nil_eob) do
          {
            'applicant_name' => { 'first' => 'John', 'last' => 'Doe' },
            'applicant_ssn' => '123456789',
            'applicant_gender' => 'male',
            'applicant_primary_provider' => 'Some Provider',
            'applicant_primary_eob' => nil,
            'form_number' => '10-7959C'
          }
        end
        let(:mapper) { described_class.new(data_with_nil_eob) }

        it 'returns Off for EOB radio' do
          expect(fields['primary_eob_radio']).to eq('Off')
        end
      end
    end

    context 'secondary insurance' do
      it 'returns nil for secondary employer radio when no secondary provider' do
        expect(fields['secondary_through_employer_radio']).to be_nil
      end

      it 'returns Off for secondary EOB radio when no secondary eob' do
        expect(fields['secondary_eob_radio']).to eq('Off')
      end

      it 'returns Off for all secondary insurance type radios' do
        expect(fields['secondary_insurance_hmo']).to eq('Off')
        expect(fields['secondary_insurance_ppo']).to eq('Off')
        expect(fields['secondary_insurance_medicaid']).to eq('Off')
        expect(fields['secondary_insurance_medigap']).to eq('Off')
        expect(fields['secondary_insurance_other']).to eq('Off')
      end
    end
  end
end
