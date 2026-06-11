# frozen_string_literal: true

require 'rails_helper'

RSpec.describe DebtsApi::Concerns::SubmissionValidation do
  let(:base_validator) { described_class::BaseValidator }
  let(:fsr_validator) { described_class::FSRValidator }
  let(:dispute_validator) { described_class::DisputeDebtValidator }
  let(:invalid_payload_message) { 'Invalid request payload schema' }

  describe 'BaseValidator' do
    describe '.validate_form_schema' do
      it 'does not raise when disputes array is valid for the schema' do
        disputes = [
          {
            'composite_debt_id' => '71166',
            'deduction_code' => '71',
            'original_ar' => 166.67,
            'current_ar' => 120.4,
            'benefit_type' => 'CH35',
            'dispute_reason' => 'Test'
          }
        ]
        expect { base_validator.validate_form_schema(disputes, 'dispute_debts.json') }
          .not_to raise_error
      end

      it 'raises FormInvalid when disputes array fails schema validation' do
        disputes = []
        expect { base_validator.validate_form_schema(disputes, 'dispute_debts.json') }
          .to raise_error(DebtsApi::Concerns::SubmissionValidation::BaseValidator::FormInvalid, invalid_payload_message)
      end

      it 'raises FormInvalid when required property is missing' do
        disputes = [{ 'composite_debt_id' => '123' }]
        expect { base_validator.validate_form_schema(disputes, 'dispute_debts.json') }
          .to raise_error(DebtsApi::Concerns::SubmissionValidation::BaseValidator::FormInvalid, invalid_payload_message)
      end
    end
  end

  describe 'FSRValidator' do
    let(:valid_form) do
      {
        'selectedDebtsAndCopays' => [
          {
            'debtType' => 'DEBT',
            'resolutionOption' => 'waiver'
          }
        ],
        'additionalData' => {
          'additionalComments' => 'I need help with this debt.'
        }
      }
    end

    it 'does not raise when a required supporting statement is present' do
      expect { fsr_validator.validate_supporting_statement(valid_form) }.not_to raise_error
    end

    it 'raises UnprocessableEntity with the expected detail when the statement is blank' do
      form = valid_form.deep_dup
      form['additionalData']['additionalComments'] = ' '

      expect { fsr_validator.validate_supporting_statement(form) }
        .to raise_error(Common::Exceptions::UnprocessableEntity) do |error|
          expect(error.errors.first.detail).to eq('Supporting personal statement is required')
        end
    end

    it 'treats nil, empty string, and whitespace as a blank statement' do
      [nil, '', '   '].each do |blank_value|
        form = valid_form.deep_dup
        form['additionalData']['additionalComments'] = blank_value

        expect { fsr_validator.validate_supporting_statement(form) }
          .to raise_error(Common::Exceptions::UnprocessableEntity),
              "expected raise for additionalComments=#{blank_value.inspect}"
      end
    end

    it 'raises for each resolution option that requires a supporting statement' do
      %w[compromise hardship-suspension monthly waiver].each do |option|
        form = valid_form.deep_dup
        form['selectedDebtsAndCopays'].first['resolutionOption'] = option
        form['additionalData']['additionalComments'] = nil

        expect { fsr_validator.validate_supporting_statement(form) }
          .to raise_error(Common::Exceptions::UnprocessableEntity),
              "expected raise for resolutionOption=#{option}"
      end
    end

    it 'does not raise when selected resolution options do not require a supporting statement' do
      form = valid_form.deep_dup
      form['selectedDebtsAndCopays'].first['resolutionOption'] = 'extended'
      form['additionalData']['additionalComments'] = nil

      expect { fsr_validator.validate_supporting_statement(form) }.not_to raise_error
    end

    it 'raises when a required option is selected alongside a non-required option and statement is blank' do
      form = valid_form.deep_dup
      form['selectedDebtsAndCopays'] = [
        { 'debtType' => 'DEBT', 'resolutionOption' => 'extended' },
        { 'debtType' => 'DEBT', 'resolutionOption' => 'monthly' }
      ]
      form['additionalData']['additionalComments'] = nil

      expect { fsr_validator.validate_supporting_statement(form) }
        .to raise_error(Common::Exceptions::UnprocessableEntity)
    end
  end

  describe 'DisputeDebtValidator' do
    let(:user) { build(:user, :loa3) }
    let(:valid_metadata) do
      {
        'disputes' => [
          { 'composite_debt_id' => '71166', 'deduction_code' => '71', 'original_ar' => 166.67,
            'current_ar' => 120.4, 'benefit_type' => 'CH35', 'dispute_reason' => 'Test' }
        ]
      }.to_json
    end
    let(:mock_service) { instance_double(DebtManagementCenter::DebtsService) }
    let(:mock_debt) { { 'compositeDebtId' => '71166' } }

    before do
      allow(DebtManagementCenter::DebtsService).to receive(:new).with(user).and_return(mock_service)
      allow(mock_service).to receive(:get_debts_by_ids).and_return([mock_debt])
    end

    describe '.validate_form_schema' do
      it 'validates disputes from metadata against schema and validates debts exist for user' do
        expect { dispute_validator.validate_form_schema(valid_metadata, user) }.not_to raise_error
        expect(mock_service).to have_received(:get_debts_by_ids).with(['71166'])
      end

      it 'raises FormInvalid when debts do not exist for user' do
        allow(mock_service).to receive(:get_debts_by_ids).and_return([])
        expect { dispute_validator.validate_form_schema(valid_metadata, user) }
          .to raise_error(DebtsApi::Concerns::SubmissionValidation::BaseValidator::FormInvalid, invalid_payload_message)
      end

      it 'raises FormInvalid when some but not all debts are missing for user' do
        metadata_two = {
          'disputes' => [
            { 'composite_debt_id' => '71166', 'deduction_code' => '71', 'original_ar' => 1, 'current_ar' => 1,
              'benefit_type' => 'CH35', 'dispute_reason' => 'Test' },
            { 'composite_debt_id' => '99999', 'deduction_code' => '71', 'original_ar' => 2, 'current_ar' => 2,
              'benefit_type' => 'CH35', 'dispute_reason' => 'Test' }
          ]
        }.to_json
        allow(mock_service).to receive(:get_debts_by_ids).and_return([mock_debt])
        expect { dispute_validator.validate_form_schema(metadata_two, user) }
          .to raise_error(DebtsApi::Concerns::SubmissionValidation::BaseValidator::FormInvalid, invalid_payload_message)
      end
    end

    describe 'validate_debt_exist_for_user' do
      it 'raises FormInvalid when disputes are empty (no composite_debt_id)' do
        expect do
          dispute_validator.send(:validate_debt_exist_for_user, [], user)
        end.to raise_error(DebtsApi::Concerns::SubmissionValidation::BaseValidator::FormInvalid,
                           invalid_payload_message)
      end

      it 'raises FormInvalid when disputes have no composite_debt_id (all nil)' do
        allow(mock_service).to receive(:get_debts_by_ids).with([nil]).and_return([])
        expect do
          dispute_validator.send(:validate_debt_exist_for_user, [{ 'other' => 'key' }], user)
        end.to raise_error(DebtsApi::Concerns::SubmissionValidation::BaseValidator::FormInvalid,
                           invalid_payload_message)
      end

      it 'raises FormInvalid when fewer debts are returned than requested' do
        allow(mock_service).to receive(:get_debts_by_ids).and_return([mock_debt])
        disputes_two = [{ 'composite_debt_id' => '71166' }, { 'composite_debt_id' => '99999' }]
        expect do
          dispute_validator.send(:validate_debt_exist_for_user, disputes_two, user)
        end.to raise_error(DebtsApi::Concerns::SubmissionValidation::BaseValidator::FormInvalid,
                           invalid_payload_message)
      end
    end
  end
end
