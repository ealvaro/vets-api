# frozen_string_literal: true

module CoeClaimFormValidation
  module LoanHistory
    extend ActiveSupport::Concern

    private

    def validate_loan_history
      lh = parsed_form['loanHistory']
      return unless lh.is_a?(Hash)

      validate_required_string_enum(lh['certificateUse'], '/loanHistory/certificateUse', CERTIFICATE_USE_VALUES)
      validate_booleanish_field(lh['hadPriorLoans'], '/loanHistory/hadPriorLoans')
      validate_loan_history_prior_loans(lh)
    end

    def validate_loan_history_prior_loans(lh)
      loans = lh['relevantPriorLoans']

      if lh.key?('relevantPriorLoans')
        unless loans.is_a?(Array)
          errors.add('/loanHistory/relevantPriorLoans', 'must be an array')
          return
        end
      else
        return
      end

      loans.each_with_index { |loan, i| validate_single_prior_loan(loan, i) }
    end
  end
end
