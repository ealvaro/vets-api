# frozen_string_literal: true

require_relative 'vba_10_8678_ibm_converter/helpers'

module SimpleFormsApi
  module Mms
    module VBA108678IbmConverter
      extend Helpers

      MAPPINGS = {
        # --- Veteran identifiers & contact ---
        'VETERAN_NAME' => ->(form) { full_name(form) },
        'LAST_4_SSN' => ->(form) { normalize_last_4_ssn(form.data['ssn']) },
        'VETERAN_ADDRESS_FULL_BLOCK' => ->(form) { veteran_address_block(form) },
        'PHONE_NUMBER' => ->(form) { phone_digits(form.data['phone']) },

        # --- Terminateing benefit ---
        'TERMINATE_BENEFIT' => ->(form) { form.data['elect_termination'] == true ? '1' : '0' },

        # --- Devices and/or medications & locations ---
        # handled in covert

        'VETERAN_SIGNATURE' => ->(form) { signature_checkbox(form) },
        'DATE_OF_VETERAN_SIGNATURE' => ->(form) { format_iso_date(form.data['signature_date']) }
      }.freeze

      def self.convert(form)
        result = MAPPINGS.transform_values { |proc| proc.call(form) }
        devices = handle_device_mappings(form.appliances_for_pdf)
        result.merge!(devices)

        result.sort.to_h
      end
    end
  end
end
