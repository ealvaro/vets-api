# frozen_string_literal: true

require_relative '../section'

module Pensions
  module PdfFill
    # Section IX: Questions regarding income and assets
    class Section9V2 < Section
      # Section configuration hash
      KEY = {
        # 9a
        'totalNetWorth' => {
          key: 'total_net_worth'
        },
        'netWorthEstimation' => {
          limit: 9,
          question_num: 9,
          question_suffix: 'A',
          question_label: 'Net Worth Estimation',
          question_text: 'NET WORTH ESTIMATION',
          key: 'net_worth_estimation',
          dollar: true
        },
        # 9b
        'transferredAssets' => {
          key: 'transferred_assets'
        },
        # 9c
        'homeOwnership' => {
          key: 'home_ownership'
        },
        # 9d
        'homeAcreageMoreThanTwo' => {
          key: 'home_acreage_more_than_two'
        },
        # 9e
        'homeAcreageValue' => {
          limit: 9,
          question_num: 9,
          question_suffix: 'C',
          question_label: 'Value of Land Over Two Acres',
          question_text: 'VALUE OF LAND OVER TWO ACRES',
          key: 'home_acreage_value',
          dollar: true
        },
        # 9f
        'landMarketable' => {
          key: 'land_marketable'
        },
        # 9g
        'incomeSourceCount' => {
          key: 'income_source_count'
        },
        'incomeSourceCountOverflow' => {
          question_num: 9,
          question_suffix: 'G',
          question_label: 'How Many Income Sources Does Your Family Have',
          question_text: 'HOW MANY INCOME SOURCES DOES YOUR FAMILY HAVE'
        },
        # 9h-k Income Sources
        'incomeSources' => {
          item_label: 'Income source',
          limit: 4,
          first_key: 'dependentName',
          # (1) Recipient
          'receiver' => {
            key: "income_recipient[#{ITERATOR}]"
          },
          'receiverOverflow' => {
            question_num: 9,
            question_suffix: '(1)',
            question_label: 'Payment Recipient',
            question_text: 'PAYMENT RECIPIENT'
          },
          'dependentName' => {
            key: "dependent_name[#{ITERATOR}]",
            limit: 24,
            question_num: 9,
            question_suffix: '(1)',
            question_label: "Child's Name",
            question_text: 'CHILD NAME'
          },
          # (2) Income Type
          'typeOfIncome' => {
            key: "income_type[#{ITERATOR}]"
          },
          'typeOfIncomeOverflow' => {
            question_num: 9,
            question_suffix: '(2)',
            question_label: 'Income Type',
            question_text: 'INCOME TYPE'
          },
          'otherTypeExplanation' => {
            key: "income_type_other[#{ITERATOR}]",
            limit: 26,
            question_num: 9,
            question_suffix: '(2)',
            question_label: 'Other Income Type Explanation',
            question_text: 'OTHER INCOME TYPE EXPLANATION'
          },
          # (3) Income Payer
          'payer' => {
            key: "income_payer[#{ITERATOR}]",
            limit: 21,
            question_num: 9,
            question_suffix: '(3)',
            question_label: 'Payer Name',
            question_text: 'PAYER NAME'
          },
          # (4) Gross Monthly Income
          'amount' => {
            limit: 10,
            question_num: 9,
            question_suffix: '(4)',
            question_label: 'Current Gross Monthly Income',
            question_text: 'CURRENT GROSS MONTHLY INCOME',
            key: "gross_monthly_income[#{ITERATOR}]",
            dollar: true
          }
        }
      }.freeze

      ##
      # Processes income and asset-related questions, converting values to expected PDF formats.
      #
      # @param form_data [Hash]
      #
      # @note Modifies `form_data`
      #
      def expand(form_data)
        form_data.merge!(
          {
            'netWorthEstimation' => expand_currency(form_data['netWorthEstimation']),
            'totalNetWorth' => to_radio_yes_no(form_data['totalNetWorth']),
            'transferredAssets' => to_radio_yes_no(form_data['transferredAssets']),
            'homeOwnership' => to_radio_yes_no(form_data['homeOwnership'])
          }
        )
        expand_home_ownership(form_data) if yes?(form_data['homeOwnership'])
        expand_income_sources(form_data)
      end

      private

      ##
      # Expands home ownership details including acreage status, valuation, and marketability.
      #
      # @param form_data [Hash] the form data hash containing home ownership attributes
      #
      # @return [void]
      #
      # @note Modifies `form_data` in place
      #
      def expand_home_ownership(form_data)
        form_data['homeAcreageMoreThanTwo'] = to_radio_yes_no(form_data['homeAcreageMoreThanTwo'])
        if yes?(form_data['homeAcreageMoreThanTwo'])
          form_data.merge!(
            {
              'homeAcreageValue' => expand_currency(form_data['homeAcreageValue']),
              'landMarketable' => to_radio_yes_no(form_data['landMarketable'])
            }
          )
        end
      end

      ##
      # Expands and normalizes income source details based on total income source counts.
      #
      # @param form_data [Hash] the form data hash containing income source fields
      #
      # @return [void]
      #
      # @note Modifies `form_data` in place
      #
      def expand_income_sources(form_data)
        form_data.merge!(
          {
            'incomeSourceCountOverflow' => form_data['incomeSourceCount']&.humanize,
            'incomeSourceCount' => INCOME_SOURCE_COUNT.fetch(form_data['incomeSourceCount'],
                                                             INCOME_SOURCE_COUNT['NONE'])
          }
        )
        return if form_data['incomeSourceCount'] == INCOME_SOURCE_COUNT['NONE']

        case form_data['incomeSourceCount']
        when INCOME_SOURCE_COUNT['ONE_TO_FOUR']
          form_data['incomeSources'] = merge_income_sources(form_data['incomeSources'])
        when INCOME_SOURCE_COUNT['FIVE_PLUS']
          ssa_income = form_data['incomeSources']&.find { |source| social_security?(source['typeOfIncome']) }
          if ssa_income.present?
            ssa_income['payer'] = SOCIAL_SECURITY_ADMINISTRATION
            form_data['incomeSources'] = merge_income_sources([ssa_income])
          end
        end
      end

      ##
      # Checks if a given income type value corresponds to Social Security.
      #
      # @param value [String] the income type identifier or key to check
      #
      # @return [Boolean] true if the value matches Social Security, false otherwise
      #
      def social_security?(value)
        INCOME_TYPES[value] == INCOME_TYPES['SOCIAL_SECURITY']
      end

      ##
      # Merge all income sources together and normalize the data.
      #
      # @param income_sources [Array<Hash>]
      #
      # @return [Array<Hash>] The merged and normalized income sources
      #
      def merge_income_sources(income_sources)
        income_sources&.map do |source|
          source.merge!(
            { 'receiver' => RECIPIENTS[source['receiver']],
              'receiverOverflow' => source['receiver']&.humanize,
              'typeOfIncome' => INCOME_TYPES.fetch(source['typeOfIncome'], INCOME_TYPES['OTHER']),
              'typeOfIncomeOverflow' => source['typeOfIncome']&.humanize,
              'amount' => expand_currency(source['amount']) }
          )
        end
      end
    end
  end
end
