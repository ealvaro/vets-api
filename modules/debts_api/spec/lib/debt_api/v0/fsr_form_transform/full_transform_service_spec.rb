# frozen_string_literal: true

require 'rails_helper'
require 'debts_api/v0/fsr_form_transform/full_transform_service'

RSpec.describe DebtsApi::V0::FsrFormTransform::FullTransformService, type: :service do
  describe '#transform' do
    context 'standard FSR' do
      let(:pre_transform_fsr_form_data) do
        get_fixture_absolute('modules/debts_api/spec/fixtures/pre_submission_fsr/pre_transform')
      end
      let(:post_transform_fsr) do
        get_fixture_absolute('modules/debts_api/spec/fixtures/pre_submission_fsr/post_transform')
      end
      let(:transformed) do
        described_class.new(pre_transform_fsr_form_data).transform
      end

      it 'reports streamlined and type' do
        expect(StatsD).to receive(:increment).with('api.fsr_submission.full_transform.no_streamlined_data')
        expect(StatsD).to receive(:increment).with('api.fsr_submission.none_streamlined_type')

        transformed
      end

      it 'generates personalIdentification' do
        expect(transformed['personalIdentification']).to eq(post_transform_fsr['personalIdentification'])
      end

      it 'generates personalData' do
        expect(transformed['personalData']).to eq(post_transform_fsr['personalData'])
      end

      it 'generates income' do
        expect(transformed['income']).to eq(post_transform_fsr['income'])
      end

      it 'generates expenses' do
        expect(transformed['expenses']).to eq(post_transform_fsr['expenses'])
      end

      it 'generates discretionaryIncome' do
        expect(transformed['discretionaryIncome']).to eq(post_transform_fsr['discretionaryIncome'])
      end

      it 'generates assets' do
        expect(transformed['assets']).to eq(post_transform_fsr['assets'])
      end

      it 'generates installmentContractsAndOtherDebts' do
        transformed_installments = transformed['installmentContractsAndOtherDebts']
        expect(transformed_installments).to eq(post_transform_fsr['installmentContractsAndOtherDebts'])
      end

      it 'generates totalOfInstallmentContractsAndOtherDebts' do
        transformed_total_installments = transformed['totalOfInstallmentContractsAndOtherDebts']
        expect(transformed_total_installments).to eq(post_transform_fsr['totalOfInstallmentContractsAndOtherDebts'])
      end

      it 'generates additionalData' do
        transformed_addl_data = transformed['additionalData']
        expect(transformed_addl_data).to eq(post_transform_fsr['additionalData'])
      end

      it 'generates applicantCertifications' do
        trans_signature = transformed['applicantCertifications']['veteranSignature']
        expect(trans_signature).to eq(post_transform_fsr['applicantCertifications']['veteranSignature'])
        expect(transformed['applicantCertifications']['veteranDateSigned']).to eq(Time.zone.today.strftime('%m/%d/%Y'))
      end

      it 'generates selectedDebtsAndCopays' do
        expect(transformed['selectedDebtsAndCopays']).to eq(post_transform_fsr['selectedDebtsAndCopays'])
      end

      it 'generates streamlined' do
        expect(transformed['streamlined']).to eq(post_transform_fsr['streamlined'])
      end
    end

    context 'zero income notice' do
      let(:pre_transform_fsr_form_data) do
        get_fixture_absolute('modules/debts_api/spec/fixtures/pre_submission_fsr/pre_transform')
      end
      let(:employment_history) { pre_transform_fsr_form_data.dig('personal_data', 'employment_history') }
      let(:veteran_records) { employment_history.dig('veteran', 'employment_records') }
      let(:veteran_record) { veteran_records.first }
      let(:spouse_record) { employment_history.dig('spouse', 'sp_employment_records').first }
      let(:transformed) { described_class.new(pre_transform_fsr_form_data).transform }

      it 'is false when no record was flagged' do
        veteran_record['gross_monthly_income'] = '0.00'
        expect(transformed['zeroIncomeSeen']).to be(false)
      end

      it 'is true when a flagged veteran record has zero income' do
        veteran_record.merge!('zero_income_seen' => true, 'gross_monthly_income' => '0.00')
        expect(transformed['zeroIncomeSeen']).to be(true)
      end

      it 'ignores spouse records entirely' do
        spouse_record.merge!('zero_income_seen' => true, 'gross_monthly_income' => '0')
        expect(StatsD).not_to receive(:increment).with(/zero_income/)
        allow(StatsD).to receive(:increment)
        expect(transformed['zeroIncomeSeen']).to be(false)
      end

      it 'is false when the flagged record reports income' do
        veteran_record['zero_income_seen'] = true
        expect(veteran_record['gross_monthly_income']).to eq('102.55')
        expect(transformed['zeroIncomeSeen']).to be(false)
      end

      it 'is false when the flag and the zero income are on different records' do
        second_job = veteran_records[0].merge('gross_monthly_income' => '0.00', 'employer_name' => 'Second Job')
        veteran_records[0].merge!('zero_income_seen' => true, 'gross_monthly_income' => '102.55')
        veteran_records << second_job
        expect(transformed['zeroIncomeSeen']).to be(false)
      end

      it 'ignores prior jobs, which never carry an income figure' do
        expect(employment_history.dig('veteran', 'employment_records').last)
          .not_to have_key('gross_monthly_income')
        expect(StatsD).not_to receive(:increment).with(/zero_income/)
        allow(StatsD).to receive(:increment)
        transformed
      end

      it 'counts a zero income record that was never flagged' do
        veteran_record['gross_monthly_income'] = '0.00'
        expect(StatsD).to receive(:increment).with(/zero_income\.no_alert/)
        allow(StatsD).to receive(:increment)
        transformed
      end

      it 'reports nothing when every record has income and none was flagged' do
        expect(StatsD).not_to receive(:increment).with(/zero_income/)
        allow(StatsD).to receive(:increment)
        transformed
      end

      it 'logs the uuid when a user is given' do
        user = build(:user, :loa3)
        veteran_record['gross_monthly_income'] = '0.00'
        expect(Rails.logger).to receive(:info).with(/zero income:.*UUID #{user.uuid}/)
        described_class.new(pre_transform_fsr_form_data, user).transform
      end

      it 'logs without a uuid when no user is given' do
        veteran_record['gross_monthly_income'] = '0.00'
        expect(Rails.logger).to receive(:info).with(/zero income:.*UUID $/)
        transformed
      end
    end

    context 'maximal FSR' do
      let(:pre_transform_fsr_form_data) do
        get_fixture_absolute('modules/debts_api/spec/fixtures/pre_submission_fsr/kitchen_sink/pre_transform')
      end
      let(:post_transform_fsr) do
        get_fixture_absolute('modules/debts_api/spec/fixtures/pre_submission_fsr/kitchen_sink/post_transform')
      end
      let(:transformed) do
        described_class.new(pre_transform_fsr_form_data).transform
      end

      it 'generates personalIdentification' do
        expect(transformed['personalIdentification']).to eq(post_transform_fsr['personalIdentification'])
      end

      it 'generates personalData' do
        expect(transformed['personalData']).to eq(post_transform_fsr['personalData'])
      end

      it 'generates income' do
        expect(transformed['income']).to eq(post_transform_fsr['income'])
      end

      it 'generates expenses' do
        expect(transformed['expenses']).to eq(post_transform_fsr['expenses'])
      end

      it 'generates discretionaryIncome' do
        expect(transformed['discretionaryIncome']).to eq(post_transform_fsr['discretionaryIncome'])
      end

      it 'generates assets' do
        expect(transformed['assets']).to eq(post_transform_fsr['assets'])
      end

      it 'generates installmentContractsAndOtherDebts' do
        trans_installments = transformed['installmentContractsAndOtherDebts']
        expect(trans_installments).to eq(post_transform_fsr['installmentContractsAndOtherDebts'])
      end

      it 'generates totalOfInstallmentContractsAndOtherDebts' do
        trans_total_installments = transformed['totalOfInstallmentContractsAndOtherDebts']
        expect(trans_total_installments).to eq(post_transform_fsr['totalOfInstallmentContractsAndOtherDebts'])
      end

      it 'generates additionalData' do
        expect(transformed['additionalData']).to eq(post_transform_fsr['additionalData'])
      end

      it 'generates applicantCertifications' do
        trans_sig = transformed['applicantCertifications']['veteranSignature']
        expect(trans_sig).to eq(post_transform_fsr['applicantCertifications']['veteranSignature'])
        expect(transformed['applicantCertifications']['veteranDateSigned']).to eq(Time.zone.today.strftime('%m/%d/%Y'))
      end

      it 'generates selectedDebtsAndCopays' do
        expect(transformed['selectedDebtsAndCopays']).to eq(post_transform_fsr['selectedDebtsAndCopays'])
      end

      it 'generates streamlined' do
        expect(transformed['streamlined']).to eq(post_transform_fsr['streamlined'])
      end
    end

    context 'streamlined short FSR' do
      let(:pre_transform_fsr_form_data) do
        get_fixture_absolute('modules/debts_api/spec/fixtures/pre_submission_fsr/sw_short/minimal_asset_pre_transform')
      end
      let(:post_transform_fsr) do
        get_fixture_absolute('modules/debts_api/spec/fixtures/pre_submission_fsr/sw_short/minimal_asset_post_transform')
      end
      let(:transformed) do
        described_class.new(pre_transform_fsr_form_data).transform
      end

      it 'generates personalIdentification' do
        expect(transformed['personalIdentification']).to eq(post_transform_fsr['personalIdentification'])
      end

      it 'generates personalData' do
        expect(transformed['personalData']).to eq(post_transform_fsr['personalData'])
      end

      it 'generates income' do
        expect(transformed['income']).to eq(post_transform_fsr['income'])
      end

      it 'generates expenses' do
        expect(transformed['expenses']).to eq(post_transform_fsr['expenses'])
      end

      it 'generates discretionaryIncome' do
        expect(transformed['discretionaryIncome']).to eq(post_transform_fsr['discretionaryIncome'])
      end

      it 'generates assets' do
        expect(transformed['assets']).to eq(post_transform_fsr['assets'])
      end

      it 'generates installmentContractsAndOtherDebts' do
        trans_installments = transformed['installmentContractsAndOtherDebts']
        expect(trans_installments).to eq(post_transform_fsr['installmentContractsAndOtherDebts'])
      end

      it 'generates totalOfInstallmentContractsAndOtherDebts' do
        trans_total_installments = transformed['totalOfInstallmentContractsAndOtherDebts']
        expect(trans_total_installments).to eq(post_transform_fsr['totalOfInstallmentContractsAndOtherDebts'])
      end

      it 'generates additionalData' do
        expect(transformed['additionalData']).to eq(post_transform_fsr['additionalData'])
      end

      it 'generates applicantCertifications' do
        trans_sig = transformed['applicantCertifications']['veteranSignature']
        expect(trans_sig).to eq(post_transform_fsr['applicantCertifications']['veteranSignature'])
        expect(transformed['applicantCertifications']['veteranDateSigned']).to eq(Time.zone.today.strftime('%m/%d/%Y'))
      end

      it 'generates selectedDebtsAndCopays' do
        expect(transformed['selectedDebtsAndCopays']).to eq(post_transform_fsr['selectedDebtsAndCopays'])
      end

      it 'generates streamlined' do
        expect(transformed['streamlined']).to eq(post_transform_fsr['streamlined'])
      end
    end

    context 'streamlined long FSR' do
      let(:pre_transform_fsr_form_data) do
        get_fixture_absolute('modules/debts_api/spec/fixtures/pre_submission_fsr/sw_long/minimal_asset_pre_transform')
      end
      let(:post_transform_fsr) do
        get_fixture_absolute('modules/debts_api/spec/fixtures/pre_submission_fsr/sw_long/minimal_asset_post_transform')
      end
      let(:transformed) do
        described_class.new(pre_transform_fsr_form_data).transform
      end

      it 'generates personalIdentification' do
        expect(transformed['personalIdentification']).to eq(post_transform_fsr['personalIdentification'])
      end

      it 'generates personalData' do
        expect(transformed['personalData']).to eq(post_transform_fsr['personalData'])
      end

      it 'generates income' do
        expect(transformed['income']).to eq(post_transform_fsr['income'])
      end

      it 'generates expenses' do
        expect(transformed['expenses']).to eq(post_transform_fsr['expenses'])
      end

      it 'generates discretionaryIncome' do
        expect(transformed['discretionaryIncome']).to eq(post_transform_fsr['discretionaryIncome'])
      end

      it 'generates assets' do
        expect(transformed['assets']).to eq(post_transform_fsr['assets'])
      end

      it 'generates installmentContractsAndOtherDebts' do
        trans_installments = transformed['installmentContractsAndOtherDebts']
        expect(trans_installments).to eq(post_transform_fsr['installmentContractsAndOtherDebts'])
      end

      it 'generates totalOfInstallmentContractsAndOtherDebts' do
        trans_total_installments = transformed['totalOfInstallmentContractsAndOtherDebts']
        expect(trans_total_installments).to eq(post_transform_fsr['totalOfInstallmentContractsAndOtherDebts'])
      end

      it 'generates additionalData' do
        expect(transformed['additionalData']).to eq(post_transform_fsr['additionalData'])
      end

      it 'generates applicantCertifications' do
        trans_sig = transformed['applicantCertifications']['veteranSignature']
        expect(trans_sig).to eq(post_transform_fsr['applicantCertifications']['veteranSignature'])
        expect(transformed['applicantCertifications']['veteranDateSigned']).to eq(Time.zone.today.strftime('%m/%d/%Y'))
      end

      it 'generates selectedDebtsAndCopays' do
        expect(transformed['selectedDebtsAndCopays']).to eq(post_transform_fsr['selectedDebtsAndCopays'])
      end

      it 'generates streamlined' do
        expect(transformed['streamlined']).to eq(post_transform_fsr['streamlined'])
      end
    end
  end

  # Exercised directly rather than through #transform: IncomeCalculator digs the
  # same paths from #initialize and raises on these shapes before the zero-income
  # check is reached.
  describe '#veteran_employment_records' do
    subject(:service) { described_class.allocate }

    def records_for(form)
      service.send(:veteran_employment_records, form)
    end

    it 'returns current records for a well-formed form' do
      form = { 'personal_data' => { 'employment_history' => { 'veteran' => { 'employment_records' => [
        { 'is_current' => true, 'employer_name' => 'Acme' },
        { 'is_current' => false, 'employer_name' => 'Prior Job' }
      ] } } } }

      expect(records_for(form).pluck('employer_name')).to eq(['Acme'])
    end

    it 'returns no records when employment_records is missing' do
      expect(records_for({ 'personal_data' => {} })).to eq([])
    end

    it 'returns no records when personal_data is an array' do
      expect(records_for({ 'personal_data' => [] })).to eq([])
    end

    it 'returns no records when employment_history is an array' do
      expect(records_for({ 'personal_data' => { 'employment_history' => [] } })).to eq([])
    end
  end
end
