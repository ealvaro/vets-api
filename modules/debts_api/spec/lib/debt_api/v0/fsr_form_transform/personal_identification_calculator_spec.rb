# frozen_string_literal: true

require 'rails_helper'
require 'debts_api/v0/fsr_form_transform/personal_identification_calculator'

RSpec.describe DebtsApi::V0::FsrFormTransform::PersonalIdentificationCalculator, type: :service do
  describe '#initialize' do
    let(:pre_transform_fsr_form_data) do
      get_fixture_absolute('modules/debts_api/spec/fixtures/pre_submission_fsr/pre_transform')
    end
    let(:post_transform_fsr_form_data) do
      get_fixture_absolute('modules/debts_api/spec/fixtures/pre_submission_fsr/post_transform')
    end

    def transform_personal_id
      transformer = described_class.new(pre_transform_fsr_form_data)
      @data = transformer.transform_personal_id
    end

    describe '#transform_personal_id' do
      before do
        transform_personal_id
      end

      it 'gets ssn correct' do
        expected_ssn = post_transform_fsr_form_data['personalIdentification']['ssn']
        transformed_ssn = @data['ssn']
        expect(expected_ssn).to eq(transformed_ssn)
      end

      it 'gets file number correct' do
        expected_file_number = post_transform_fsr_form_data['personalIdentification']['fileNumber']
        transformed_file_number = @data['fileNumber']
        expect(expected_file_number).to eq(transformed_file_number)
      end

      it 'gets FSR reasons correct' do
        expected_fsr_reason = post_transform_fsr_form_data['personalIdentification']['fsrReason']
        transformed_fsr_reason = @data['fsrReason']
        expect(expected_fsr_reason).to eq(transformed_fsr_reason)
      end

      context 'when there are no selected debts and copays' do
        let(:pre_transform_fsr_form_data) do
          raw_data = get_fixture_absolute('modules/debts_api/spec/fixtures/pre_submission_fsr/pre_transform')
          raw_data['selected_debts_and_copays'] = []
          raw_data
        end

        it 'returns an empty string for FSR reason' do
          expected_fsr_reason = ''
          transformed_fsr_reason = @data['fsrReason']
          expect(expected_fsr_reason).to eq(transformed_fsr_reason)
        end
      end

      context 'when a debt has a hardship-suspension resolution option' do
        let(:pre_transform_fsr_form_data) do
          raw_data = get_fixture_absolute('modules/debts_api/spec/fixtures/pre_submission_fsr/pre_transform')
          raw_data['selected_debts_and_copays'] = [
            {
              'resolution_option' => 'hardship-suspension',
              'hardship_timeframe' => '6-to-12-months',
              'hardship_timeframe_acknowledgement' => true
            }
          ]
          raw_data
        end

        it 'maps hardship-suspension to its display name in fsrReason' do
          expect(@data['fsrReason']).to eq('Hardship suspension')
        end
      end

      context 'when debts have a mix of resolution options including hardship-suspension' do
        let(:pre_transform_fsr_form_data) do
          raw_data = get_fixture_absolute('modules/debts_api/spec/fixtures/pre_submission_fsr/pre_transform')
          raw_data['selected_debts_and_copays'] = [
            { 'resolution_option' => 'waiver', 'resolution_comment' => '' },
            { 'resolution_option' => 'hardship-suspension',
              'hardship_timeframe' => 'within-6-months',
              'hardship_timeframe_acknowledgement' => true }
          ]
          raw_data
        end

        it 'joins unique display names with comma' do
          expect(@data['fsrReason']).to eq('Waiver, Hardship suspension')
        end
      end
    end
  end
end
