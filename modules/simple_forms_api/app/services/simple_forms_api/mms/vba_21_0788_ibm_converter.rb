# frozen_string_literal: true

require_relative 'vba_21_0788_ibm_converter/helpers'

module SimpleFormsApi
  module Mms
    module VBA210788IbmConverter
      extend Helpers

      # Per the QS data dictionary "Form Type" header row (no comma).
      FORM_TYPE_LABEL = 'VA FORM 21-0788 FEB 2026'

      MAX_APPORTIONEES = 4

      MAPPINGS = {
        # veteran info
        'VETERAN_NAME' => ->(form) { combined_name(form, 'full_name') },
        'VETERAN_SSN' => ->(form) { normalize_ssn(form.data['ssn']) },
        'VA_FILE_NUMBER' => ->(form) { (form.data['va_file_number'] || '').to_s.delete('-') },
        'VETERAN_DOB' => ->(form) { format_iso_date(form.data['date_of_birth']) },
        # preparer/claimant
        'CLAIMANT_NAME' => ->(form) { combined_name(form, 'preparer') },
        'CURRENT_SPOUSE' => ->(form) { form.data['relationship_to_veteran'] == 'spouse' ? 1 : 0 },
        'CHILD_18_23_IN_SCHOOL' => ->(form) { form.data['relationship_to_veteran'] == 'child_18_23' ? 1 : 0 },
        'CUSTODIAN' => ->(form) { form.data['relationship_to_veteran'] == 'custodian' ? 1 : 0 },
        'DEPENDENT_PARENT' => ->(form) { form.data['relationship_to_veteran'] == 'parent' ? 1 : 0 },
        'CHILD_OVER_18' => ->(form) { form.data['relationship_to_veteran'] == 'child_disabled' ? 1 : 0 },
        'OTHER' => ->(form) { form.data['relationship_to_veteran'] == 'other' ? 1 : 0 },
        'OTHER_SPECIFY' => ->(form) { form.data['other_relationship_description'] || '' },
        'CLAIMANT_ADDRESS_FULL_BLOCK' => ->(form) { claimant_address_block(form) },
        'CLAIMANT_TELEPHONE_NUMBER' => ->(form) { phone_digits(form.data['phone']) },
        'CLAIMANT_EMAIL_ADDRESS' => ->(form) { form.data['email_address'] || form.data['email'] || '' },
        # APPORTIONMENT INFORMATION
        # handled in #apportion_section

        'VETERAN_STEP_CHILD_YES' => ->(form) { form.data['stepchild_living_in_household'] == true ? 1 : 0 },
        'VETERAN_STEP_CHILD_NO' => ->(form) { form.data['stepchild_living_in_household'] == false ? 1 : 0 },
        # 'VETERAN_STEP_CHILD_DATE' <- handled in #apportion_section
        'VETERAN_CHILD_ADOPTED_YES' => ->(form) { form.data['legally_adopted'] == true ? 1 : 0 },
        'VETERAN_CHILD_ADOPTED_NO' => ->(form) { form.data['legally_adopted'] == false ? 1 : 0 },

        # 13A Reasons for Apportionment
        # handled in #reason_checkbox_fields
        # typo field expained above
        # 'PRIMARY _BENEFICIARY_RESIDES_OUTSIDE_US' => ->(_) {},

        'BENEFICIARY_FACILITY_NAME' => ->(form) { form.facility_name || '' },
        'BENEFICIARY_FACILITY_ADDRESS_FULL_BLOCK' => ->(form) { form.facility_address || '' },
        'REMARKS' => ->(form) { form.data['remarks'] || '' },
        'CLAIMANT_SIGNATURE' => ->(form) { form.signature.present? ? 'Yes' : 'No' },
        'CLAIMANT_SIGNATURE_DATE' => ->(form) { format_iso_date(form.signature_date) },

        # --- Bottom-left form type, page 1 and page 2 ---
        'FORM_TYPE_1' => ->(_) { FORM_TYPE_LABEL },
        'FORM_TYPE' => ->(_) { FORM_TYPE_LABEL }
      }.freeze

      def self.convert(form)
        result = MAPPINGS.transform_values { |proc| proc.call(form) }
        result.merge!(apportion_section(form.data['apportionment_people'], MAX_APPORTIONEES))
        result.merge!(reason_checkbox_fields(form.data))

        result.sort.to_h
      end
    end
  end
end
