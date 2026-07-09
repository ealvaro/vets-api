# frozen_string_literal: true

module IvcChampva
  module FormMappers
    class VHA1010d2027
      include Base

      def initialize(data)
        @data = data
      end

      def mapped_fields # rubocop:disable Metrics/MethodLength
        vet = @data['veteran'] || {}
        applicants = @data['applicants'] || []

        fields = {
          'veteran_last_name' => name_with_suffix(vet.dig('full_name', 'last'), vet.dig('full_name', 'suffix')),
          'veteran_first_name' => vet.dig('full_name', 'first'),
          'veteran_middle_initial' => middle_initial(vet.dig('full_name', 'middle')),
          'veteran_ssn' => vet['ssn_or_tin'],
          'veteran_street_address' => vet.dig('address', 'street_combined'),
          'veteran_city' => vet.dig('address', 'city'),
          'veteran_state' => vet.dig('address', 'state'),
          'veteran_zip' => vet.dig('address', 'postal_code'),
          'veteran_country' => vet.dig('address', 'country'),
          'veteran_phone' => vet['phone_number'],
          'veteran_email' => vet['email'],
          'veteran_dob' => vet['date_of_birth'],
          'veteran_date_of_marriage' => vet['date_of_marriage'],
          'sponsor_is_deceased_radio' => vet['sponsor_is_deceased'] ? 0 : 1,
          'veteran_date_of_death' => vet['date_of_death'],
          'is_active_service_death_radio' => vet['is_active_service_death'] ? 0 : 1
        }

        3.times do |i|
          app = applicants[i] || {}
          prefix = "applicant_#{i + 1}"
          fields.merge!(applicant_fields(app, prefix))
        end

        fields.merge!(certification_fields)
        fields['form1'] = @data['form1']
        fields
      end

      private

      def applicant_fields(app, prefix)
        {
          "#{prefix}_last_name" => name_with_suffix(app.dig('applicant_name', 'last'),
                                                    app.dig('applicant_name', 'suffix')),
          "#{prefix}_first_name" => app.dig('applicant_name', 'first'),
          "#{prefix}_middle_initial" => middle_initial(app.dig('applicant_name', 'middle')),
          "#{prefix}_ssn" => app['ssn_or_tin'],
          "#{prefix}_dob" => app['applicant_dob'],
          "#{prefix}_street_address" => app.dig('applicant_address', 'street_combined'),
          "#{prefix}_city" => app.dig('applicant_address', 'city'),
          "#{prefix}_state" => app.dig('applicant_address', 'state'),
          "#{prefix}_zip" => app.dig('applicant_address', 'postal_code'),
          "#{prefix}_email" => app['applicant_email_address'],
          "#{prefix}_phone" => app['applicant_phone'],
          "#{prefix}_gender_radio" => gender_radio(app.dig('applicant_gender', 'gender')),
          "#{prefix}_medicare_radio" => app.dig('applicant_medicare_status', 'eligibility') == 'enrolled' ? 1 : 0,
          "#{prefix}_ohi_radio" => app.dig('applicant_has_ohi', 'has_ohi') == 'yes' ? 1 : 0,
          "#{prefix}_relationship" => app['vet_relationship']
        }
      end

      def certification_fields
        cert = @data['certification'] || {}
        {
          'statement_of_truth_signature' => @data['statement_of_truth_signature'],
          'certification_date' => cert['date'],
          'contact_email' => @data.dig('primary_contact_info', 'email'),
          'certifier_last_name' => cert['last_name'],
          'certifier_first_name' => cert['first_name'],
          'certifier_middle_initial' => middle_initial(cert['middle_initial']),
          'certifier_relationship' => cert['relationship'],
          'certifier_street_address' => cert['street_address'],
          'certifier_city' => cert['city'],
          'certifier_state' => cert['state'],
          'certifier_zip' => cert['postal_code'],
          'certifier_phone' => cert['phone_number']
        }
      end
    end
  end
end
