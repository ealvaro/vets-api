# frozen_string_literal: true

module SimpleFormsApi
  module Mms
    module VBA214140IbmConverter
      FORM_TYPE_LABEL = 'VA FORM 21-4140, AUG 2024'
      SUPPORTED_DATE_FORMATS = [
        '%m/%d/%Y', # 02/24/2026
        '%Y-%m-%d',  # 2026-02-24
        '%m-%d-%Y',  # 02-24-2026
        '%Y/%m/%d'   # 2026/02/24
      ].freeze

      MAPPINGS = {
        'VETERAN_NAME' => ->(form) { full_name(form) },
        'VETERAN_FIRST_NAME' => ->(form) { form.first_name || '' },
        'VETERAN_INITIAL' => ->(form) { form.middle_initial || '' },
        'VETERAN_LAST_NAME' => ->(form) { form.last_name || '' },
        'VETERAN_SSN' => ->(form) { normalize_ssn(form.ssn) },
        'VETERAN_SSN_1' => ->(form) { normalize_ssn(form.ssn) },
        'VA_FILE_NUMBER' => ->(form) { form.data.dig('id_number', 'va_file_number') || '' },
        'VETERAN_DOB' => ->(form) { format_date(form.dob) },
        'VETERAN_SERVICE_NUMBER' => ->(form) { form.data['service_number'] || '' },
        'EMAIL' => ->(form) { form.notification_email_address || '' },
        'PHONE_NUMBER' => ->(form) { normalize_phone(form.phone_primary) },
        'VETERAN_ADDRESS_LINE1' => ->(form) { form&.address&.address_line1 || '' },
        'VETERAN_ADDRESS_LINE2' => ->(form) { form&.address&.address_line2 || '' },
        'VETERAN_ADDRESS_CITY' => ->(form) { form&.address&.city || '' },
        'VETERAN_ADDRESS_STATE' => ->(form) { form&.address&.state_code || '' },
        'VETERAN_ADDRESS_COUNTRY' => ->(form) { form&.address&.country_code_iso2 || '' },
        'VETERAN_ADDRESS_ZIP5' => ->(form) { normalize_zip(form&.address&.zip_code) },
        'VETERAN_ADDRESS_FULL_BLOCK' => lambda do |form|
          [
            form&.address&.address_line1 || '',
            form&.address&.address_line2 || '',
            city_state_zip_string(form),
            form&.address&.country_code_iso2 || ''
          ].compact.reject(&:empty?).join("\n")
        end,
        'EMPLOYER_NAME_ADDRESS' => ->(form) { form.employment_history[0]&.name_and_address || '' },
        'EMPLOYER_NAME_ADDRESS1' => ->(form) { form.employment_history[1]&.name_and_address || '' },
        'EMPLOYER_NAME_ADDRESS2' => ->(form) { form.employment_history[2]&.name_and_address || '' },
        'EMPLOYER_NAME_ADDRESS3' => ->(form) { form.employment_history[3]&.name_and_address || '' },
        'VETERAN_SIGNATURE' => ->(form) { form.signature_employed || form.signature_unemployed || '' },
        'DATE_SIGNED' => ->(form) { format_date(form.signature_date_employed || form.signature_date_unemployed) },
        'FORM_TYPE' => ->(_) { FORM_TYPE_LABEL },
        'FORM_TYPE_1' => ->(_) { FORM_TYPE_LABEL }
      }.freeze

      def self.convert(form)
        MAPPINGS.transform_values { |proc| proc.call(form) }.sort.to_h
      end

      # ---------- Helpers ----------
      def self.full_name(form)
        [form.first_name, form.middle_initial, form.last_name].compact&.join(' ')&.strip || ''
      end

      def self.normalize_ssn(ssn_array)
        return '' if ssn_array.nil?

        ssn_array&.join&.gsub(/\D/, '') || ''
      end

      def self.normalize_phone(phone)
        return '' if phone.nil?

        phone&.to_s&.gsub(/\D/, '') || ''
      end

      def self.normalize_zip(zip)
        return '' if zip.nil?

        zip&.to_s&.gsub(/\D/, '')&.[](0, 5) || ''
      end

      def self.city_state_zip_string(form)
        "#{form&.address&.city || ''}, #{form&.address&.state_code || ''} #{normalize_zip(form&.address&.zip_code)}"
      end

      def self.format_date(date)
        return '' if date.blank?

        date = date.join('-') if date.is_a?(Array)

        cleaned = date.to_s.delete('"')

        SUPPORTED_DATE_FORMATS.each do |format|
          return Date.strptime(cleaned, format).strftime('%m/%d/%Y')
        rescue ArgumentError
          next
        end

        ''
      end
    end
  end
end
