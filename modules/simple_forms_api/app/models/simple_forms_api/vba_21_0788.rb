# frozen_string_literal: true

require_rel '../form_engine'
require 'simple_forms_api/overflow_210788'

module SimpleFormsApi
  class VBA210788 < BaseForm
    STATS_KEY = 'api.simple_forms_api.21_0788'
    FORM_NUMBER = '21-0788'
    REMARKS_LIMIT = 461
    RELATIONSHIP_LIMIT = 105
    TABLE_OTHER_LIMIT = 25

    APPORTIONMENT_RADIOS = [
      [7, 6],
      [12, 10],
      [8, 9],
      [13, 11]
    ].freeze

    INCARCERATION_BLOCKS = {
      veteran_incarcerated: {
        main: 2,
        felony: 3,
        misdemeanor: 4
      },
      spouse_or_child_incarcerated: {
        main: 5,
        felony: 6,
        misdemeanor: 7
      }
    }.freeze

    SINGLE_REASONS = {
      veteran_incompetent_no_fiduciary: 8,
      veteran_pension_care_facility: 9,
      enemy_territory_resident: 10,
      veteran_disappeared: 11
    }.freeze

    attr_reader :address

    def initialize(data)
      super

      @address = FormEngine::Address.new(
        address_line1: data.dig('address', 'street'),
        address_line2: data.dig('address', 'street2'),
        city: data.dig('address', 'city'),
        country_code_iso3: data.dig('address', 'country'),
        state_code: data.dig('address', 'state'),
        zip_code: data.dig('address', 'postal_code')
      )
    end

    def first_name
      data.dig('full_name', 'first')
    end

    def middle_name
      data.dig('full_name', 'middle')
    end

    def last_name
      data.dig('full_name', 'last')
    end

    def full_name(full_name_object = nil)
      if full_name_object
        [
          full_name_object['first'],
          full_name_object['middle'],
          full_name_object['last']
        ].compact.join(' ')
      else
        [
          first_name,
          middle_name,
          last_name
        ].compact.join(' ')
      end
    end

    def notification_first_name
      first_name
    end

    def notification_last_name
      last_name
    end

    def notification_email_address
      data['email_address'].presence
    end

    def track_user_identity(confirmation_number)
      identity = 'submission'
      StatsD.increment("#{STATS_KEY}.#{identity}")
      Rails.logger.info('Simple forms api - 21-0788 submission user identity', identity:, confirmation_number:)
    end

    def ssn
      data['ssn']
    end

    def file_number
      data['va_file_number']
    end

    def metadata_file_number
      [
        file_number,
        ssn
      ].find(&:present?).to_s.gsub(/\D/, '')
    end

    def full_address
      [
        @address.address_line1,
        @address.address_line2,
        @address.city,
        @address.state_code,
        @address.zip_code
      ].compact.join(', ')
    end

    def zip_code_is_us_based
      data.dig('address', 'country').to_s.upcase == 'USA'
    end

    def zip_code
      data.dig('address', 'postal_code')
    end

    def phone
      format_phone(data['phone'])
    end

    def email
      data['email']
    end

    def stepchild_living_in_household?
      data['stepchild_living_in_household']
    end

    def relationship
      data['relationship_to_veteran']
    end

    def legally_adopted?
      data['legally_adopted']
    end

    def on_behalf_of_child
      data['on_behalf_of_child']
    end

    def facility_name
      data['facility_name']
    end

    def facility_address
      data['facility_address']
    end

    def remarks
      if data['remarks'].present?
        data['remarks'].length < REMARKS_LIMIT ? data['remarks'] : 'See Additional Page'
      else
        ''
      end
    end

    def signature
      data['statement_of_truth_signature']
    end

    # Returns the formatted signature_date from the form object or the current Date
    def signature_date
      return Time.current.in_time_zone('America/Chicago').strftime('%m/%d/%Y') unless data['signature_date']

      Date.parse(data['signature_date']).strftime('%m/%d/%Y')
    end

    def other_relationship_text
      clip_text_for_length(data['other_relationship_description'], RELATIONSHIP_LIMIT)
    end

    def people
      data['apportionment_people'] || []
    end

    def apportionment_fields
      mapped = {}

      people.first(4).each_with_index do |person, i|
        mapped["form1[0].Page_1[0].NAMEVETERAN[#{3 + i}]"] = person['full_name']
        mapped["form1[0].Page_1[0].NAMEVETERAN[#{7 + i}]"] = person['ssn']
        mapped["form1[0].Page_1[0].NAMEVETERAN[#{11 + i}]"] = apportionment_fields_relationship(person)

        yes_idx, no_idx = APPORTIONMENT_RADIOS[i]

        if person['currently_receiving']
          mapped["form1[0].Page_1[0].RadioButtonList[#{yes_idx}]"] = '1'
        else
          mapped["form1[0].Page_1[0].RadioButtonList[#{no_idx}]"] = '1'
        end
      end

      mapped
    end

    def apportionment_fields_relationship(person)
      if person['relationship'] == 'other'
        clip_text_for_length(person['other_relationship_description'], TABLE_OTHER_LIMIT)
      else
        person['relationship']
      end
    end

    def departure_date
      dates = people.map do |p|
        if p['is_stepchild'] == true && p['stepchild_lives_with_veteran'] == false
          next if p['stepchild_departure_date'].blank?
          next unless parsable_date?(p['stepchild_departure_date'])

          Date.strptime(p['stepchild_departure_date']).strftime('%m/%d/%Y')
        end
      end.compact
      dates.join(',')
    end

    def incarceration_fields
      # 2 = Veteran is incarcerated for more than 60 days...
      # 3 felony
      # 4 misdemeanor
      # 5 = Surviving spouse or child is incarcerated for more than 60 days...
      # 6 felony
      # 7 misdemeanor
      # 8 = Veteran is incompetent, without fiduciary,receiving hospital, nursing home, or domiciliary care
      # 9 = Veteran is in receipt of pension and is receiving hospital, domiciliary or nursing home care
      # 10 = The primary beneficiary resides under the control of an enemny
      # 11 = The veteran has disappeared for 90 days or more and his/her whereabouts remain unknown
      mapped = {}

      (2..11).each do |i|
        mapped["form1[0].Page_2[0].RadioButtonList[#{i}]"] = 'Off'
      end

      reason = data['reason']
      incarceration = data['incarceration'] || {}

      block = INCARCERATION_BLOCKS[reason&.to_sym]

      if block
        mapped["form1[0].Page_2[0].RadioButtonList[#{block[:main]}]"] = '0'

        mapped["form1[0].Page_2[0].RadioButtonList[#{block[:felony]}]"] =
          incarceration['felony'] ? '0' : 'Off'

        mapped["form1[0].Page_2[0].RadioButtonList[#{block[:misdemeanor]}]"] =
          incarceration['misdemeanor'] ? '0' : 'Off'
      end

      SINGLE_REASONS.each do |key, idx|
        mapped["form1[0].Page_2[0].RadioButtonList[#{idx}]"] =
          reason == key.to_s ? '0' : 'Off'
      end

      mapped
    end

    # -------------------------
    # Stamping
    # -------------------------

    def desired_stamps
      return [] if signature.blank?

      [{
        coords: [50, 340],
        text: signature,
        page: 1
      }]
    end

    def submission_date_stamps(timestamp = Time.current)
      [
        {
          coords: [460, 690],
          text: 'Application Submitted:',
          page: 0,
          font_size: 12
        },
        {
          coords: [460, 670],
          text: timestamp.in_time_zone('UTC').strftime('%H:%M %Z %D'),
          page: 0,
          font_size: 12
        }
      ]
    end

    # -------------------------
    # Metadata
    # -------------------------

    def metadata
      {
        'veteranFirstName' => first_name,
        'veteranLastName' => last_name,
        'fileNumber' => metadata_file_number,
        'zipCode' => zip_code,
        'source' => 'VA Platform Digital Forms',
        'docType' => doc_type,
        'businessLine' => 'CMP'
      }
    end

    def doc_type
      if Flipper.enabled?(:simple_forms_s3_mms_prefix_bugfix)
        "StructuredData:#{data['form_number'].presence || FORM_NUMBER}"
      else
        data['form_number'].presence || FORM_NUMBER
      end
    end

    def format_phone(phone)
      return nil if phone.nil?

      "#{phone[0...-7]}-#{phone[-7...-4]}-#{phone[-4..]}"
    end

    # -------------------------
    # Overflow
    # -------------------------
    def overflow_pdf
      people_for = people.select do |p|
        p['relationship'] == 'other' &&
          p['other_relationship_description'].present? &&
          p['other_relationship_description'].length > TABLE_OTHER_LIMIT
      end
      claimant_is_other = data['relationship_to_veteran'] == 'other' && data['other_relationship_description'].present?
      remarks_over_limit = remarks == 'See Additional Page'
      # nothing qualifies for overflow so return early
      return nil if people_for.length.zero? && claimant_is_other == false && !remarks_over_limit

      overflow_data = {}
      if data['other_relationship_description'].length > RELATIONSHIP_LIMIT
        overflow_data['question_6'] = data['other_relationship_description']
      end
      overflow_data['people_for'] = people_for if people_for.length.positive?
      overflow_data['remarks'] = data['remarks'] if remarks_over_limit

      # Overflow Object as nothing in it, so return
      return nil if overflow_data.values_at('question_6', 'people_for', 'remarks').all?(&:blank?)

      Overflow210788.new(overflow_data, cutoff: 1).generate
    end

    private

    def parsable_date?(str)
      Date.parse(str)
      true
    rescue ArgumentError
      false
    end

    def clip_text_for_length(string, length = 50)
      return '' if string.nil?
      return string if length.nil?

      string.length > length ? "See Add'l page" : string
    end
  end
end
