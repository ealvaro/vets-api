# frozen_string_literal: true

require_relative 'vba_21_4502_ibm_converter/helpers'
require_relative 'vba_21_4502_ibm_converter/unused_fields'

module SimpleFormsApi
  module Mms
    module VBA214502IbmConverter
      extend Helpers
      extend UnusedFields

      FORM_TYPE_LABEL = 'VA FORM 21-4502, AUG 2024'

      MAPPINGS = {
        'VETERAN_FIRST_NAME' => ->(form) { form.data.dig('full_name', 'first') || '' },
        'VETERAN_MIDDLE_INITIAL' => ->(form) { (form.data.dig('full_name', 'middle') || '')[0, 1] || '' },
        'VETERAN_LAST_NAME' => ->(form) { form.data.dig('full_name', 'last') || '' },

        'VETERAN_SSN' => ->(form) { normalize_ssn(form.data['ssn']) },
        'VETERAN_SSN_1' => ->(form) { normalize_ssn(form.data['ssn']) },

        'VA_FILE_NUMBER' => ->(form) { (form.data['va_file_number'] || '').to_s.gsub(/\D/, '') },

        'VETERAN_DOB' => ->(form) { date_parts_to_string(form, 'dob') },

        'VETERAN_SERVICE_NUMBER' => ->(form) { (form.data['va_service_number'] || '').to_s.gsub(/-/, '') },

        'PHONE_NUMBER' => ->(form) { domestic_phone(form) },
        'INT_PHONE_NUMBER' => ->(form) { international_phone(form) },

        'EMAIL' => ->(form) { form.data['email'] || '' },
        'AGREE_ELECTRONIC_CORR' => ->(form) { bool_to_checkbox(form.data['electronic_correspondence']) },

        'CURRENT_ADDRESS_LINE1' => ->(form) { current_address(form)['street'] || '' },
        'CURRENT_ADDRESS_LINE2' => ->(form) { current_address(form)['street2'] || '' },
        'CURRENT_ADDRESS_CITY' => ->(form) { current_address(form)['city'] || '' },
        'CURRENT_ADDRESS_STATE' => ->(form) { current_address(form)['state'] || '' },
        'CURRENT_ADDRESS_COUNTRY' => ->(form) { current_address(form)['country'] || '' },
        'CURRENT_ADDRESS_ZIP5' => ->(form) { normalize_zip(current_address(form)['postal_code']) },

        'PLANNED_ADDRESS_LINE1' => ->(form) { planned_address(form)['street'] || '' },
        'PLANNED_ADDRESS_LINE2' => ->(form) { planned_address(form)['street2'] || '' },
        'PLANNED_ADDRESS_CITY' => ->(form) { planned_address(form)['city'] || '' },
        'PLANNED_ADDRESS_STATE' => ->(form) { planned_address(form)['state'] || '' },
        'PLANNED_ADDRESS_COUNTRY' => ->(form) { planned_address(form)['country'] || '' },
        'PLANNED_ADDRESS_ZIP5' => ->(form) { normalize_zip(planned_address(form)['postal_code']) },

        'BRANCH_OF_SERVICE_ARMY' => ->(form) { branch_checkbox(form, 'ARMY') },
        'BRANCH_OF_SERVICE_NAVY' => ->(form) { branch_checkbox(form, 'NAVY') },
        'BRANCH_OF_SERVICE_AIR-FORCE' => ->(form) { branch_checkbox(form, 'AIR-FORCE') },
        'BRANCH_OF_SERVICE_MARINE' => ->(form) { branch_checkbox(form, 'MARINE') },
        'BRANCH_OF_SERVICE_COAST-GUARD' => ->(form) { branch_checkbox(form, 'COAST-GUARD') },
        'BRANCH_OF_SERVICE_SPACE' => ->(form) { branch_checkbox(form, 'SPACE') },
        'BRANCH_OF_SERVICE_NOAA' => ->(form) { branch_checkbox(form, 'NOAA') },
        'BRANCH_OF_SERVICE_USPHS' => ->(form) { branch_checkbox(form, 'USPHS') },

        'ACTIVE_DUTY_YES' => ->(form) { yes_checkbox(form.data['active_duty']) },
        'ACTIVE_DUTY_NO' => ->(form) { no_checkbox(form.data['active_duty']) },

        'PLACE_ENTERED_ACTIVE_SERVICE' => ->(form) { form.data['place_of_entry'] || '' },
        'DATE_ENTERED_TO_SERVICE' => ->(form) { date_parts_to_string(form, 'date_of_entry') },
        'PLACE_SEPARATED_FROM_SERVICE' => ->(form) { form.data['place_of_release'] || '' },
        'DATE_SEPARATED_FROM_SERVICE' => ->(form) { date_parts_to_string(form, 'date_of_release') },

        'APPLIED_DISABILITY_YES' => ->(form) { yes_checkbox(form.data['applied_for_compensation']) },
        'APPLIED_DISABILITY_NO' => ->(form) { no_checkbox(form.data['applied_for_compensation']) },
        'APPLIED_DISABILITY_PLACE' => ->(form) { form.data['name_of_office'] || '' },
        'DATE_APPLIED_DISABILITY' => ->(form) { date_parts_to_string(form, 'date_applied_for_compensation') },

        'VA_LOCATION_WITH_FILE' => ->(form) { form.data['location_of_office'] || '' },

        'TYPE_CONVEYANCE_AUTO' => ->(form) { conveyance_checkbox(form, 'AUTO') },
        'TYPE_CONVEYANCE_STAT_WAGON' => ->(form) { conveyance_checkbox(form, 'STAT_WAGON') },
        'TYPE_CONVEYANCE_VAN' => ->(form) { conveyance_checkbox(form, 'VAN') },
        'TYPE_CONVEYANCE_TRUCK' => ->(form) { conveyance_checkbox(form, 'TRUCK') },
        'TYPE_CONVEYANCE_OTHER' => ->(form) { conveyance_other_checkbox(form) },
        'TYPE_CONVEYANCE_OTHER_SPECIFY' => ->(form) { conveyance_other_value(form) },

        'PREVIOUS_APPLIED_YES' => ->(form) { yes_checkbox(form.data['previously_applied']) },
        'PREVIOUS_APPLIED_NO' => ->(form) { no_checkbox(form.data['previously_applied']) },
        'DATE_PREVIOUS_APPLIED' => ->(form) { date_parts_to_string(form, 'date_of_previous_application') },
        'PLACE_PREVIOUS_APPLIED' => ->(form) { form.data['previous_application_location'] || '' },

        'VETERAN_SIGNATURE' => ->(form) { form.data['statement_of_truth_signature'].present? ? 1 : 0 },
        'DATE_OF_VETERAN_SIGNATURE' => ->(form) { date_parts_to_string(form, 'signature_date') },

        'FORM_TYPE' => ->(_) { FORM_TYPE_LABEL },
        'FORM_TYPE_1' => ->(_) { FORM_TYPE_LABEL }
      }.freeze

      def self.convert(form)
        result = MAPPINGS.transform_values { |proc| proc.call(form) }
        result.merge!(unused_fields).sort.to_h
      end
    end
  end
end
