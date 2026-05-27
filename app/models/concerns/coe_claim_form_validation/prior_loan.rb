# frozen_string_literal: true

module CoeClaimFormValidation
  module PriorLoan
    extend ActiveSupport::Concern

    private

    def validate_single_prior_loan(loan, i)
      base = "/loanHistory/relevantPriorLoans/#{i}"
      unless loan.is_a?(Hash)
        errors.add(base, 'must be an object')
        return
      end

      validate_prior_loan_va_number(loan, base)
      validate_coe_date_range(loan['dateRange'], base)
      validate_prior_loan_property_address(loan, base)
      validate_prior_loan_natural_disaster(loan, base)
      validate_optional_loan_number_field(loan, "#{base}/loanAmount", 'loanAmount')
      validate_optional_loan_number_field(loan, "#{base}/loanEntitlementCharged", 'loanEntitlementCharged')
    end

    def validate_prior_loan_va_number(loan, base)
      number = loan['vaLoanNumber']
      return if number.blank?

      unless number.is_a?(String) || number.is_a?(Numeric)
        errors.add("#{base}/vaLoanNumber", 'must be a string or number')
        return
      end
      return if number.to_s.strip.match?(VA_LOAN_NUMBER_12_PATTERN)

      errors.add("#{base}/vaLoanNumber", 'must be a 12-digit VA loan number')
    end

    def validate_prior_loan_property_address(loan, base)
      pa = loan['propertyAddress']
      if pa.blank?
        errors.add("#{base}/propertyAddress", 'is required')
      elsif !pa.is_a?(Hash)
        errors.add("#{base}/propertyAddress", 'must be an object')
      else
        validate_prior_loan_address_fields("#{base}/propertyAddress", pa)
      end
    end

    def validate_prior_loan_address_fields(fragment, pa)
      %w[country street1 city state postalCode].each { |f| validate_required_string(pa[f], "#{fragment}/#{f}") }
      %w[street2 street3].each do |f|
        validate_optional_string(pa[f], "#{fragment}/#{f}") if pa.key?(f)
      end

      validate_postal_code(pa['postalCode'], "#{fragment}/postalCode")
      validate_state_code(pa['state'], "#{fragment}/state")

      { 'street1' => 50, 'street2' => 50, 'street3' => 50, 'city' => 51 }.each do |field, max|
        val = pa[field]
        errors.add("#{fragment}/#{field}", "must be #{max} characters or less") if val.is_a?(String) && val.length > max
      end
    end

    def validate_prior_loan_natural_disaster(loan, base)
      nd = loan['naturalDisaster']
      return if nd.blank?

      unless nd.is_a?(Hash)
        errors.add("#{base}/naturalDisaster", 'must be an object')
        return
      end

      validate_booleanish_field(nd['affected'], "#{base}/naturalDisaster/affected")
      return unless coe_truthy?(nd['affected'])

      dol = nd['dateOfLoss']
      if dol.blank?
        errors.add("#{base}/naturalDisaster/dateOfLoss", 'is required when affected is true')
      elsif !dol.is_a?(String)
        errors.add("#{base}/naturalDisaster/dateOfLoss", 'must be a string')
      elsif !coe_date_string_valid?(dol)
        errors.add("#{base}/naturalDisaster/dateOfLoss", 'must be a valid date')
      end
    end

    def validate_optional_loan_number_field(loan, fragment, key)
      return unless loan.key?(key)

      value = loan[key]
      return if value.nil? || value == ''

      errors.add(fragment, 'must be a string or number') unless value.is_a?(String) || value.is_a?(Numeric)
    end
  end
end
