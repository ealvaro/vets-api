# frozen_string_literal: true

require 'rails_helper'

RSpec.describe IvcChampva::FormMappers::VHA107959a2027 do
  let(:fixture_data) do
    JSON.parse(File.read('modules/ivc_champva/spec/fixtures/form_json/vha_10_7959a_2027.json'))
  end
  let(:form) { IvcChampva::VHA107959a2027.new(fixture_data) }
  let(:mapper) { described_class.new(form.data) }
  let(:fields) { mapper.mapped_fields }

  describe '#mapped_fields' do
    it 'returns a Hash' do
      expect(fields).to be_a(Hash)
    end

    context 'applicant fields' do
      it 'maps applicant middle initial' do
        expect(fields['applicant_middle_initial']).to be_nil
      end

      it 'maps applicant first name' do
        expect(fields['applicant_first_name']).to eq('GI')
      end

      it 'maps applicant last name' do
        expect(fields['applicant_last_name']).to eq('Joe')
      end

      it 'maps applicant member number' do
        expect(fields['applicant_member_number']).to eq('12345678')
      end
    end

    context 'sponsor fields' do
      it 'maps sponsor middle initial' do
        expect(fields['sponsor_middle_initial']).to eq('Q')
      end

      it 'maps sponsor last name' do
        expect(fields['sponsor_last_name']).to eq('Jones')
      end
    end

    context 'new address radio' do
      it 'returns 1 when applicant_new_address is empty string' do
        expect(fields['new_address_radio']).to eq(1)
      end

      context 'when applicant_new_address is "no"' do
        let(:no_data) { fixture_data.deep_dup.tap { |d| d['applicant_new_address'] = 'no' } }
        let(:form) { IvcChampva::VHA107959a2027.new(no_data) }

        it 'returns 0' do
          expect(fields['new_address_radio']).to eq(0)
        end
      end
    end

    context 'OHI radio' do
      it 'returns yes label when has_ohi is truthy' do
        expect(fields['has_ohi_radio']).to eq('Yes (check type and provide coverage information below)')
      end

      context 'when has_ohi is false' do
        let(:no_ohi_data) { fixture_data.deep_dup.tap { |d| d['has_ohi'] = false } }
        let(:form) { IvcChampva::VHA107959a2027.new(no_ohi_data) }

        it 'returns no label' do
          expect(fields['has_ohi_radio']).to eq('No (proceed to Section III)')
        end
      end
    end

    context 'policy type radio' do
      it 'returns employer sponsored label for group type' do
        expect(fields['policy_type_radio']).to eq('Employer sponsored (group) ')
      end

      context 'when type is nonGroup' do
        let(:non_group_data) do
          fixture_data.deep_dup.tap { |d| d['policies'][0]['type'] = 'nonGroup' }
        end
        let(:form) { IvcChampva::VHA107959a2027.new(non_group_data) }

        it 'returns private label' do
          expect(fields['policy_type_radio']).to eq('Private (non group) ')
        end
      end

      context 'when type is medicare' do
        let(:medicare_data) do
          fixture_data.deep_dup.tap { |d| d['policies'][0]['type'] = 'medicare' }
        end
        let(:form) { IvcChampva::VHA107959a2027.new(medicare_data) }

        it 'returns medicare label' do
          expect(fields['policy_type_radio']).to eq('Medicare (Part A or B) ')
        end
      end

      context 'when type is other' do
        let(:other_data) do
          fixture_data.deep_dup.tap { |d| d['policies'][0]['type'] = 'other' }
        end
        let(:form) { IvcChampva::VHA107959a2027.new(other_data) }

        it 'returns other label' do
          expect(fields['policy_type_radio']).to eq('Other (Specify):')
        end
      end
    end

    context 'claims radios' do
      it 'returns Yes for work related' do
        expect(fields['claim_is_work_related_radio']).to eq('Yes')
      end

      it 'returns Yes for auto related' do
        expect(fields['claim_is_auto_related_radio']).to eq('Yes')
      end

      context 'when claims are not related' do
        let(:no_related) do
          fixture_data.deep_dup.tap do |d|
            d['claims'][0]['claim_is_work_related'] = false
            d['claims'][0]['claim_is_auto_related'] = false
          end
        end
        let(:form) { IvcChampva::VHA107959a2027.new(no_related) }

        it 'returns No for both' do
          expect(fields['claim_is_work_related_radio']).to eq('No')
          expect(fields['claim_is_auto_related_radio']).to eq('No')
        end
      end
    end

    context 'certifier relationship' do
      it 'returns other relationship when certifier_relationship is "other"' do
        expect(fields['certifier_relationship']).to eq(fixture_data['certifier_other_relationship'])
      end

      context 'when certifier_relationship is not other' do
        let(:self_data) do
          fixture_data.deep_dup.tap { |d| d['certifier_relationship'] = 'self' }
        end
        let(:form) { IvcChampva::VHA107959a2027.new(self_data) }

        it 'returns the relationship value directly' do
          expect(fields['certifier_relationship']).to eq('self')
        end
      end
    end

    context 'policy details' do
      it 'maps policy 1 fields' do
        expect(fields['policy_1_name']).to eq('BCBS')
        expect(fields['policy_1_number']).to eq('123')
        expect(fields['policy_1_phone']).to eq('1231231234')
      end

      it 'maps policy 2 fields' do
        expect(fields['policy_2_name']).to eq('Cigna')
        expect(fields['policy_2_number']).to eq('321')
      end
    end
  end
end
