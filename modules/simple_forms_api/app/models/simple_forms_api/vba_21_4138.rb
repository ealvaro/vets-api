# frozen_string_literal: true

require 'simple_forms_api/overflow_pdf_generator'

module SimpleFormsApi
  class VBA214138 < BaseForm
    STATS_KEY = 'api.simple_forms_api.21_4138'
    REMARKS_SLICE_1 = 0..1510
    REMARKS_SLICE_2 = 1511..3685
    ALLOTTED_REMARKS_LAST_INDEX = REMARKS_SLICE_2.end
    CLAIMANT_TYPE_VETERAN = 'self'

    def desired_stamps
      [{
        coords: [[35, 220]],
        text: data['statement_of_truth_signature'],
        page: 1
      }]
    end

    def submission_date_stamps(timestamp = Time.current)
      [
        {
          coords: [460, 710],
          text: 'Application Submitted:',
          page: 0,
          font_size: 12
        },
        {
          coords: [460, 690],
          text: timestamp.in_time_zone('UTC').strftime('%H:%M %Z %D'),
          page: 0,
          font_size: 12
        }
      ]
    end

    def metadata
      id_data = veteran_id_data
      {
        'veteranFirstName' => veteran_full_name['first'],
        'veteranLastName' => veteran_full_name['last'],
        'fileNumber' => id_data['va_file_number'].presence || id_data['ssn'],
        'zipCode' => veteran_mailing_address['postal_code'],
        'source' => 'VA Platform Digital Forms',
        'docType' => data['form_number'],
        'businessLine' => 'CMP'
      }
    end

    def veteran_full_name
      if veteran_is_filing?
        # for self/veteran, profile confirms name as top-level first/middle/last
        name = {
          'first' => data['first'],
          'middle' => data['middle'],
          'last' => data['last']
        }.compact_blank
        name.presence || data['full_name'] || {}
      else
        # for non-veteran claimant, veteran's name is in veteran_full_name
        data['veteran_full_name'].presence || {}
      end
    end

    def veteran_id_data
      data['veteran_id_number'].presence || data['id_number'] || {}
    end

    def veteran_mailing_address
      data['veteran_mailing_address'].presence ||
        parse_profile_mailing_address ||
        {}
    end

    def veteran_phone
      data['veteran_phone'].presence ||
        parse_profile_phone
    end

    def veteran_email
      data['veteran_email_address'].presence ||
        data.dig('veteran', 'email', 'email_address')
    end

    def veteran_date_of_birth
      data['veteran_date_of_birth'].presence || data['date_of_birth']
    end

    def notification_first_name
      veteran_is_filing? ? data['first'] : data.dig('full_name', 'first')
    end

    def notification_email_address
      veteran_email
    end

    def zip_code_is_us_based
      veteran_mailing_address['country'] == 'USA'
    end

    def remarks_with_claimant_header
      statement = data['statement'].to_s
      return statement if veteran_is_filing?

      "#{build_claimant_header}\n\n#{statement}"
    end

    def overflow_pdf
      full_remarks = remarks_with_claimant_header
      return nil if full_remarks.length <= ALLOTTED_REMARKS_LAST_INDEX

      header_offset = full_remarks.length - data['statement'].to_s.length
      cutoff = [ALLOTTED_REMARKS_LAST_INDEX - header_offset, 0].max

      SimpleFormsApi::OverflowPdfGenerator
        .new(data, cutoff:)
        .generate
    end

    def track_user_identity(confirmation_number); end

    def veteran_is_filing?
      data['claimant_type'] == CLAIMANT_TYPE_VETERAN
    end

    def build_claimant_header
      first = data.dig('full_name', 'first').to_s
      last  = data.dig('full_name', 'last').to_s
      name  = [first, last].compact_blank.join(' ')

      relationship = if data['relationship_to_veteran'] == 'notListed'
                       data['relationship_to_veteran_other'].to_s
                     else
                       data['relationship_to_veteran'].to_s
                     end

      "Submitted by: #{name.presence || 'Not provided'} (#{relationship.presence || 'Not provided'})"
    end

    private

    def parse_profile_mailing_address
      addr = data.dig('veteran', 'mailing_address')
      return nil if addr.blank?

      {
        'street' => addr['address_line1'],
        'city' => addr['city'],
        'state' => addr['state_code'],
        'postal_code' => addr['zip_code'],
        'country' => addr['country_code_iso3'] || 'USA'
      }
    end

    def parse_profile_phone
      phone = data.dig('veteran', 'mobile_phone')
      return nil if phone.blank?

      "#{phone['area_code']}#{phone['phone_number']}"
    end
  end
end
