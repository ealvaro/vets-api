# frozen_string_literal: true

require_relative 'vba_21_0788_ibm_converter/helpers'

module SimpleFormsApi
  module Mms
    module VBA210788IbmConverter
      extend Helpers

      # Per the QS data dictionary "Form Type" header row (no comma).
      FORM_TYPE_LABEL = 'VA FORM 21-0788 FEB 2026'

      MAX_APPORTIONEES = 4

      # Box 6 — relationship radio value (from the PDF renderer's RadioButtonList
      # order) => DD checkbox field. Note child_18_23 and child_disabled map to
      # *different* DD fields.
      RELATIONSHIP_CHECKBOXES = {
        'CURRENT_SPOUSE' => 'spouse',
        'CHILD_18_23_IN_SCHOOL' => 'child_18_23',
        'CUSTODIAN' => 'custodian',
        'DEPENDENT_PARENT' => 'parent',
        'CHILD_OVER_18' => 'child_disabled'
      }.freeze

      # Box 13a — apportionment reason value => DD checkbox field.
      # TODO: confirm the left-hand reason keys against the form's submitted
      # JSON (see `apportionment_reason` in helpers).
      REASON_CHECKBOXES = {
        'VETERAN_INCARCERATED' => 'veteran_incarcerated',
        'VETERAN_INCARCERATED_FELONY' => 'veteran_incarcerated_felony',
        'VETERAN_INCARCERATED_MISDEMEANOR' => 'veteran_incarcerated_misdemeanor',
        'SURVIVING_SPOUSE_INCARCERATED' => 'surviving_spouse_incarcerated',
        'SURVIVING_SPOUSE_OR_CHILD_INCARCERATED_FELONY' => 'surviving_spouse_or_child_incarcerated_felony',
        'SURVIVING_SPOUSE_OR_CHILD_INCARCERATED_MISDEMEANOR' => 'surviving_spouse_or_child_incarcerated_misdemeanor',
        'VETERAN_INCOMPETENT' => 'veteran_incompetent',
        'VETERAN_IN_RECEIPT_OF_PENSION' => 'veteran_in_receipt_of_pension',
        # Field name below is verbatim from the data dictionary, including the
        # space after PRIMARY and the OUTSUDE misspelling. Do not "fix" it.
        'PRIMARY _BENEFICIARY_RESIDES_OUTSUDE_US' => 'primary_beneficiary_resides_outside_us',
        'VETERAN_DISAPPEARED' => 'veteran_disappeared'
      }.freeze

      MAPPINGS = {
        # --- Box 1: Veteran identification ---
        'VETERAN_FIRST_NAME' => ->(form) { name_part(form, 'full_name', 'first') },
        'VETERAN_MIDDLE_INITIAL' => ->(form) { middle_initial(form, 'full_name') },
        'VETERAN_LAST_NAME' => ->(form) { name_part(form, 'full_name', 'last') },
        'VETERAN_NAME' => ->(form) { combined_name(form, 'full_name') },

        # --- Boxes 2-4 ---
        'VETERAN_SSN' => ->(form) { normalize_ssn(form.data['ssn']) },
        # DD type is AlphaNumeric, format note "Without Dashes" - keep any
        # legacy alpha prefix (e.g. "C12345678"), strip dashes only.
        'VA_FILE_NUMBER' => ->(form) { (form.data['va_file_number'] || '').to_s.delete('-') },
        'VETERAN_DOB' => ->(form) { format_iso_date(form.data['date_of_birth']) },

        # --- Box 5: Claimant / individual acting on behalf of a minor child ---
        'CLAIMANT_FIRST_NAME' => ->(form) { name_part(form, 'claimant_full_name', 'first') },
        'CLAIMANT_MIDDLE_INITIAL' => ->(form) { middle_initial(form, 'claimant_full_name') },
        'CLAIMANT_LAST_NAME' => ->(form) { name_part(form, 'claimant_full_name', 'last') },
        'CLAIMANT_NAME' => ->(form) { combined_name(form, 'claimant_full_name') },

        # --- Box 6: Relationship to veteran (checkboxes + OTHER free text) ---
        # OTHER is Generic Text in the DD: carries the typed-in relationship,
        # not a checkbox value.
        'OTHER' => ->(form) { other_relationship(form) },

        # --- Boxes 7-9: Claimant contact ---
        'CLAIMANT_ADDRESS_FULL_BLOCK' => ->(form) { claimant_address_block(form) },
        'CLAIMANT_TELEPHONE_NUMBER' => ->(form) { phone_digits(form.data['phone']) },
        'CLAIMANT_EMAIL_ADDRESS' => ->(form) { form.data['email_address'] || '' },

        # --- Box 11: Stepchild ---
        'VETERAN_STEP_CHILD_DATE' => ->(form) { format_iso_date(form.data['stepchild_left_household_date']) },

        # --- Box 13b: Beneficiary facility ---
        'BENEFICIARY_FACILITY_NAME' => ->(form) { form.data['facility_name'] || '' },
        'BENEFICIARY_FACILITY_ADDRESS_FULL_BLOCK' => ->(form) { facility_address_block(form) },

        # --- Boxes 14-15 ---
        'REMARKS' => ->(form) { form.data['remarks'] || '' },
        'CLAIMANT_SIGNATURE' => ->(form) { signature_checkbox(form) },
        'CLAIMANT_SIGNATURE_DATE' => ->(form) { format_iso_date(form.data['signature_date']) },

        # --- Bottom-left form type, page 1 and page 2 ---
        'FORM_TYPE_1' => ->(_) { FORM_TYPE_LABEL },
        'FORM_TYPE' => ->(_) { FORM_TYPE_LABEL }
      }.freeze

      def self.convert(form)
        result = MAPPINGS.transform_values { |proc| proc.call(form) }

        result.merge!(relationship_checkbox_fields(form))
        result.merge!(reason_checkbox_fields(form))
        result.merge!(stepchild_yes_no_fields(form))

        apportionees = Array(form.data['apportionment_recipients']).first(MAX_APPORTIONEES)
        (1..MAX_APPORTIONEES).each do |i|
          result.merge!(apportionee_fields(apportionees[i - 1] || {}, i))
        end

        result.sort.to_h
      end
    end
  end
end
