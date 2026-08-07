# frozen_string_literal: true

module Pensions
  module PdfFill
    # Constants used for PDF mapping
    module Constants
      # TODO: Inconsistent singular and plural enum constant names

      # Veteran's marital status
      MARITAL_STATUS = {
        'MARRIED' => 0,
        'SEPARATED' => 1,
        'WIDOWED' => 2,
        'DIVORCED' => 2,
        'NEVER_MARRIED' => 2
      }.freeze

      # Type of marriage between veteran and current spouse
      #
      # @note CEREMONY is from legacy FE component. Keeping for compatibility.
      #       FE component also sends TRIBAL, COMMON_LAW, and PROXY. All of which is treated as OTHER
      MARRIAGE_TYPE = {
        'CEREMONY' => 0,
        'RELIGIOUS' => 0,
        'CIVIL' => 0,
        'OTHER' => 1
      }.freeze

      # V2: Reason for current marital separation
      REASON_FOR_SEPARATION = {
        'MEDICAL_CARE' => 0,
        'RELATIONSHIP' => 1,
        'LOCATION' => 2,
        'OTHER' => 3
      }.freeze

      # V2: Reason for previous marital separation
      REASON_FOR_MARRIAGE_END = {
        'DEATH' => 0,
        'DIVORCE' => 1,
        'OTHER' => 2
      }.freeze

      # TODO: Remove after version migration complete
      # V1: Reason for previous marital separation
      REASONS_FOR_SEPARATION = {
        'DEATH' => 0,
        'DIVORCE' => 1,
        'OTHER' => 2
      }.freeze

      # Number of income sources reported
      #
      # @note For V2 you can no longer determine count from length of income sources array
      INCOME_SOURCE_COUNT = {
        'NONE' => 0,
        'ONE_TO_FOUR' => 1,
        'FIVE_PLUS' => 2
      }.freeze

      # Income Types
      INCOME_TYPES = {
        'SOCIAL_SECURITY' => 0,
        'INTEREST_DIVIDEND' => 1,
        'CIVIL_SERVICE' => 2,
        'PENSION_RETIREMENT' => 3,
        'OTHER' => 4
      }.freeze

      # Abbreviation for government agency
      SOCIAL_SECURITY_ADMINISTRATION = 'SSA'

      # Recipients Type
      RECIPIENTS = {
        'VETERAN' => 0,
        'SPOUSE' => 1,
        'DEPENDENT' => 2
      }.freeze

      # V1: Medical Care Types
      CARE_TYPES = {
        'CARE_FACILITY' => 0,
        'IN_HOME_CARE_PROVIDER' => 1
      }.freeze

      # V2: Medical Care Types
      CARE_TYPES_V2 = {
        'NURSING_HOME' => 0,
        'CARE_FACILITY' => 1,
        'ADULT_DAYCARE' => 2,
        'IN_HOME_CARE_PROVIDER' => 3
      }.freeze

      # Payment Frequency
      PAYMENT_FREQUENCY = {
        'ONCE_MONTH' => 0,
        'ONCE_YEAR' => 1,
        'ONE_TIME' => 2
      }.freeze

      # TODO: Capitalize here and in vets_json_schema for consistency
      # Bank account type
      ACCOUNT_TYPE = {
        'checking' => 0,
        'savings' => 1,
        'none' => 2
      }.freeze
    end
  end
end
