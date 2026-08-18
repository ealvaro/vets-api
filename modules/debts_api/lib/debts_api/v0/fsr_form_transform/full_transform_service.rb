# frozen_string_literal: true

require 'debts_api/v0/fsr_form_transform/additional_data_calculator'
require 'debts_api/v0/fsr_form_transform/asset_calculator'
require 'debts_api/v0/fsr_form_transform/expense_calculator'
require 'debts_api/v0/fsr_form_transform/income_calculator'
require 'debts_api/v0/fsr_form_transform/discretionary_income_calculator'
require 'debts_api/v0/fsr_form_transform/installment_contracts_other_debts_calculator'
require 'debts_api/v0/fsr_form_transform/personal_data_calculator'
require 'debts_api/v0/fsr_form_transform/personal_identification_calculator'
require 'debts_api/v0/fsr_form_transform/streamlined_calculator'
require 'debts_api/v0/fsr_form_transform/utils'

module DebtsApi
  module V0
    module FsrFormTransform
      class FullTransformService
        include ::FsrFormTransform::Utils

        def initialize(form, user = nil)
          @user = user
          @assets = AssetCalculator.new(form).transform_assets
          @income = IncomeCalculator.new(form).get_transformed_income
          @expenses = ExpenseCalculator.build(form).transform_expenses
          @additional_data = AdditionalDataCalculator.new(form).get_data
          @discretionary_income = DiscretionaryIncomeCalculator.new(form).get_data
          installment_calculator = InstallmentContractsOtherDebtsCalculator.new(form)
          @installment_contracts_other_debts = installment_calculator.get_data
          @total_installments = installment_calculator.get_totals_data
          @personal_data_calculator = PersonalDataCalculator.new(form)
          @personal_data = @personal_data_calculator.get_personal_data
          @personal_identification = PersonalIdentificationCalculator.new(form).transform_personal_id
          @selected_debts_and_copays = re_camel(re_dollar_cent(form['selected_debts_and_copays'],
                                                               %w[p_h_account_number pHAccountNumber]))
          @streamlined = StreamlinedCalculator.new(form).get_streamlined_data
          @zero_income_seen = zero_income_seen?(form)
        end

        def transform
          report_form_types

          {
            'income' => @income,
            'assets' => @assets,
            'expenses' => @expenses,
            'additionalData' => @additional_data,
            'discretionaryIncome' => @discretionary_income,
            'installmentContractsAndOtherDebts' => @installment_contracts_other_debts,
            'totalOfInstallmentContractsAndOtherDebts' => @total_installments,
            'personalData' => @personal_data,
            'personalIdentification' => @personal_identification,
            'applicantCertifications' => certification,
            'selectedDebtsAndCopays' => @selected_debts_and_copays,
            'streamlined' => @streamlined,
            'zeroIncomeSeen' => @zero_income_seen
          }
        end

        private

        def zero_income_seen?(form)
          alerted, not_alerted = veteran_employment_records(form).partition { |record| record['zero_income_seen'] }
          zero_with_alert, income_with_alert = alerted.partition { |record| record['gross_monthly_income'].to_f.zero? }
          zero_no_alert = not_alerted.count { |record| record['gross_monthly_income'].to_f.zero? }

          report_zero_income(zero_with_alert.size, income_with_alert.size, zero_no_alert)

          zero_with_alert.any?
        end

        def veteran_employment_records(form)
          records = form.dig('personal_data', 'employment_history', 'veteran', 'employment_records') || []
          # Prior jobs carry no gross_monthly_income at all, which would read as $0.
          # A *current* job with a blank figure still counts, on purpose — no_alert
          # tracks any missing income reaching DMC, not only a typed zero.
          records.select { |record| record['is_current'] }
        rescue TypeError
          # An array where a hash belongs, which #dig cannot walk. Strong params
          # filters the other malformed shapes; this one it lets through.
          []
        end

        def report_zero_income(zero_with_alert, income_with_alert, zero_no_alert)
          return if zero_with_alert.zero? && income_with_alert.zero? && zero_no_alert.zero?

          stats_key = DebtsApi::V0::Form5655Submission::STATS_KEY
          StatsD.increment("#{stats_key}.zero_income.confirmed") if zero_with_alert.positive?
          StatsD.increment("#{stats_key}.zero_income.discrepancy") if income_with_alert.positive?
          StatsD.increment("#{stats_key}.zero_income.no_alert") if zero_no_alert.positive?
          Rails.logger.info(
            'FsrFormTransform::FullTransformService zero income: ' \
            "#{zero_with_alert} zero with alert, #{income_with_alert} income with alert, " \
            "#{zero_no_alert} zero without alert - UUID #{@user&.uuid}"
          )
        end

        def report_form_types
          tracking_label = "full_transform.#{@streamlined['value'] ? 'has' : 'no'}_streamlined_data"
          streamlined_type = @streamlined['type']

          StatsD.increment("#{DebtsApi::V0::Form5655Submission::STATS_KEY}.#{tracking_label}")
          StatsD.increment("#{DebtsApi::V0::Form5655Submission::STATS_KEY}.#{streamlined_type}_streamlined_type")
        rescue => e
          Rails.logger.error("FsrFormTransform::FullTransformService::#report_form_types error: #{e.message}")
          nil
        end

        def certification
          {
            'veteranSignature' => @personal_data_calculator.name_str,
            'veteranDateSigned' => Time.zone.today.strftime('%m/%d/%Y')
          }
        end
      end
    end
  end
end
