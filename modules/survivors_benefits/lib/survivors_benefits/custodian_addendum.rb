# frozen_string_literal: true

require 'pdf_fill/forms/form_helper'
require 'survivors_benefits/helpers'

module SurvivorsBenefits
  ##
  # Builds the 21-4138 Remarks block documenting the custodian who signed a 21P-534EZ on
  # behalf of a child under 18.
  #
  # The 21P-534EZ AcroForm only has an alternate-signer signature (item 14A) and date
  # (item 14B) — there is no field anywhere on the form for the filer's relationship to the
  # child, mailing address, or email. Those values are recorded on the ancillary 21-4138
  # instead, so they reach the rater rather than being dropped.
  #
  # NOTE: this describes the *filer*. It is unrelated to `custodianFullName` /
  # `custodianAddress` (item 6R), which describe the custodian of the Veteran's other
  # dependent children.
  #
  class CustodianAddendum
    include ::PdfFill::Forms::FormHelper
    include SurvivorsBenefits::Helpers

    # Heading for the Remarks block, matching the form's own Section XIV wording
    HEADER = 'ALTERNATE SIGNER (CUSTODIAN) INFORMATION'

    class << self
      # @param form_data [Hash] the parsed claim form
      # @return [String, nil] the Remarks block, or nil when no custodian is filing
      def remarks(form_data)
        new(form_data).remarks
      end
    end

    # @param form_data [Hash] the parsed claim form
    def initialize(form_data)
      @form_data = form_data || {}
    end

    # @return [String, nil] header plus one labeled line per populated value, or nil when
    #   this claim is not a custodian filing
    def remarks
      return unless SurvivorsBenefits::Helpers.custodian_filing?(form_data['claimantRelationship'])

      lines = [
        ['Custodian name', full_name],
        ['Relationship to child', form_data['childRelationship']],
        ['Custodian address', address],
        ['Custodian email', form_data['filingCustodianEmail']]
      ].filter_map { |label, value| "#{label}: #{value}" if value.present? }

      [HEADER, *lines].join("\n")
    end

    private

    attr_reader :form_data

    # Middle name is truncated to a single initial by format_name.
    #
    # @return [String, nil]
    def full_name
      name = format_name(form_data['filingCustodianFullName'])
      name.values_at('first', 'middle', 'last').compact_blank.join(' ').presence
    end

    # address_block returns street / city-state-zip / country on separate lines; flatten it
    # so each Remarks entry stays on one labeled line.
    #
    # @return [String, nil]
    def address
      address_block(form_data['filingCustodianAddress'].presence)&.split("\n")&.compact_blank&.join(', ').presence
    end
  end
end
