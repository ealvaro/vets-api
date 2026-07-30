# frozen_string_literal: true

require 'survivors_benefits/helpers'

module SurvivorsBenefits::StructuredData::V2025::Section12
  ##
  # Section XII
  # Build and merge claim certification structured data entries.
  def build_section12
    signer_name = build_name(signer_full_name)[:full]
    signed_date = format_date(form['dateSigned'] || Date.current)

    fields.merge!(
      {
        'CB_FURTHER_EVD_CLAIM_SUPPORT' => false
      }
    )
    fields.merge!(claimant_signature_fields(signer_name, signed_date))
  end

  ##
  # Route the signer to the claimant line (§12) or the alternate-signer line
  # (§14) when a custodian is filing for a child under 18. Mirrors the PDF
  # signature routing so the MMS submission and the stamped PDF agree.
  #
  # @param signer_name [String, nil] full name of the person signing
  # @param signed_date [String] formatted signature date
  # @return [Hash]
  def claimant_signature_fields(signer_name, signed_date)
    if SurvivorsBenefits::Helpers.custodian_filing?(form['claimantRelationship'])
      {
        'CLAIMANT_SIGNATURE' => '',
        'DATE_OF_CLAIMANT_SIGNATURE' => '',
        'ALTERNATE_SIGNATURE' => signer_name,
        'DateAltSigned' => signed_date
      }
    else
      {
        'CLAIMANT_SIGNATURE' => signer_name,
        'DATE_OF_CLAIMANT_SIGNATURE' => signed_date,
        'ALTERNATE_SIGNATURE' => '',
        'DateAltSigned' => ''
      }
    end
  end

  ##
  # The person whose name goes on the signature line. For a custodian filing, the frontend
  # renames `yourName` to `filingCustodianFullName` but leaves the original key in the payload;
  # prefer the canonical key so this keeps working if `your*` is ever pruned, which would
  # otherwise silently put the *child's* name on the alternate-signer line.
  #
  # @return [Hash, nil]
  def signer_full_name
    form['filingCustodianFullName'].presence || form['yourName'].presence || form['claimantFullName']
  end
end
