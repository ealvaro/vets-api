# frozen_string_literal: true

module IvcChampva
  module FormMappers
    class VHA107959f22025
      include Base

      def initialize(data)
        @data = data
      end

      def mapped_fields
        vet = @data['veteran'] || {}

        {
          'send_payment_radio' => vet['send_payment'] == 'Provider' ? 1 : 0,
          'veteran_last_name' => vet.dig('full_name', 'last'),
          'veteran_first_name' => vet.dig('full_name', 'first'),
          'veteran_middle_initial' => middle_initial(vet.dig('full_name', 'middle')),
          'veteran_ssn' => vet['ssn'],
          'veteran_va_claim_number' => vet['va_claim_number'],
          'veteran_dob' => vet['date_of_birth'],
          'veteran_physical_address' => format_address_string(vet['physical_address_string']),
          'veteran_physical_country' => vet.dig('physical_address', 'country'),
          'veteran_mailing_address' => format_address_string(vet['mailing_address_string']),
          'veteran_mailing_country' => vet.dig('mailing_address', 'country'),
          'veteran_phone' => vet['phone_number'],
          'veteran_email' => vet['email_address'],
          'current_date' => @data['current_date'],
          'statement_of_truth_signature' => @data['statement_of_truth_signature'],
          'vha107959fform' => @data.fetch('vha107959fform', 'vha107959fform')
        }
      end
    end
  end
end
