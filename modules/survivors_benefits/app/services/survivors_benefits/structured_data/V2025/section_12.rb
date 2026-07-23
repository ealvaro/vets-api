# frozen_string_literal: true

require 'survivors_benefits/helpers'

module SurvivorsBenefits::StructuredData::V2025::Section12
  ##
  # Section XII
  # Build and merge claim certification structured data entries.
  def build_section12
    signer_name = build_name(form['yourName'].presence || form['claimantFullName'])[:full]
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
    if SurvivorsBenefits::Helpers.signature_field_index_for_claimant_relationship(form['claimantRelationship']).zero?
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
end
