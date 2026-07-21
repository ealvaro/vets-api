# frozen_string_literal: true

module SimpleFormsApi
  module Mms
    module VBA210788IbmConverter
      # rubocop:disable Metrics/ModuleLength
      module Helpers
        # Box 13a — apportionment reason value => DD checkbox field.
        REASON_FIELDS = {
          'VETERAN_INCARCERATED' => 'veteran_incarcerated',
          'VETERAN_INCARCERATED_FELONY' => 0,
          'VETERAN_INCARCERATED_MISDEMEANOR' => 0,
          'SURVIVING_SPOUSE_INCARCERATED' => 'spouse_or_child_incarcerated',
          'SURVIVING_SPOUSE_OR_CHILD_INCARCERATED_FELONY' => 0,
          'SURVIVING_SPOUSE_OR_CHILD_INCARCERATED_MISDEMEANOR' => 0,
          'VETERAN_INCOMPETENT' => 'veteran_incompetent_no_fiduciary',
          'VETERAN_IN_RECEIPT_OF_PENSION' => 'veteran_pension_care_facility',
          # Field name below is verbatim from the data dictionary, including the
          # space after PRIMARY and the OUTSUDE misspelling. Do not "fix" it.
          'PRIMARY _BENEFICIARY_RESIDES_OUTSUDE_US' => 'enemy_territory_resident',
          'VETERAN_DISAPPEARED' => 'veteran_disappeared'
        }.freeze

        def apportion_section(people_array, max)
          fields = { 'VETERAN_STEP_CHILD_DATE' => [] }
          if people_array.blank?
            return fields.merge(
              blank_people_array(max),
              { 'VETERAN_STEP_CHILD_DATE' => '' }
            )
          end

          max.times do |i|
            person = people_array[i]
            if person.blank?
              fields.merge!(blank_apportionment_person(i + 1))
              next
            end
            fields.merge!(populate_apportionment_fields(person, i + 1))
            if stepchild_has_left(person)
              fields['VETERAN_STEP_CHILD_DATE'].append(format_iso_date(person['stepchild_departure_date']))
            end
          end
          # move out date consolidation
          fields['VETERAN_STEP_CHILD_DATE'] = fields['VETERAN_STEP_CHILD_DATE'].join(', ')
          fields
        end

        def populate_apportionment_fields(person_hash, dd_index)
          {
            "NAME_APPORTIONMENT_REQUESTED_#{dd_index}" => person_hash['full_name'] || '',
            "APPORTION_SSN_#{dd_index}" => normalize_ssn(person_hash['ssn']) || '',
            "APPORTION_RELATIONSHIP_TO_VETERAN_#{dd_index}" => apportionment_relationship(person_hash),
            "APPORTION_CURRENTLY_IN_RECEPIENT_YES_#{dd_index}" => person_hash['currently_receiving'] ? 1 : 0,
            "APPORTION_CURRENTLY_IN_RECEPIENT_NO_#{dd_index}" => person_hash['currently_receiving'] ? 0 : 1
          }
        end

        def apportionment_relationship(person)
          return person['other_relationship_description'] || '' if person['relationship'] == 'other'

          person['relationship'] || ''
        end

        def blank_apportionment_person(dd_index)
          {
            "NAME_APPORTIONMENT_REQUESTED_#{dd_index}" => '',
            "APPORTION_SSN_#{dd_index}" => '',
            "APPORTION_RELATIONSHIP_TO_VETERAN_#{dd_index}" => '',
            "APPORTION_CURRENTLY_IN_RECEPIENT_YES_#{dd_index}" => 0,
            "APPORTION_CURRENTLY_IN_RECEPIENT_NO_#{dd_index}" => 0
          }
        end

        def blank_people_array(max)
          Array(1..max).map { |i| blank_apportionment_person(i) }.reduce({}, :merge)
        end

        def stepchild_has_left(person)
          person['is_stepchild'] == true &&
            person['stepchild_lives_with_veteran'] == false &&
            person['stepchild_departure_date'].present?
        end

        def reason_checkbox_fields(form_data)
          # reason: veteran_incarcerated
          #         spouse_or_child_incarcerated
          #         veteran_incompetent_no_fiduciary
          #         veteran_pension_care_facility
          #         enemy_territory_resident
          #         veteran_disappeared
          # incarceration: { felony: false, misdemeanor: true }
          reason = form_data['reason']
          incarcerated = form_data['incarceration']

          reason_map = REASON_FIELDS.transform_values { |value| reason == value ? 1 : 0 }
          if reason == 'veteran_incarcerated'
            reason_map['VETERAN_INCARCERATED_FELONY'] =
              incarcerated && incarcerated['felony'] ? 1 : 0
            reason_map['VETERAN_INCARCERATED_MISDEMEANOR'] =
              incarcerated && incarcerated['misdemeanor'] ? 1 : 0
          end
          if reason == 'spouse_or_child_incarcerated'
            reason_map['SURVIVING_SPOUSE_OR_CHILD_INCARCERATED_FELONY'] =
              incarcerated && incarcerated['felony'] ? 1 : 0
            reason_map['SURVIVING_SPOUSE_OR_CHILD_INCARCERATED_MISDEMEANOR'] =
              incarcerated && incarcerated['misdemeanor'] ? 1 : 0
          end

          reason_map
        end

        # ---------- Names ----------

        def name_part(form, key, part)
          name = form.data[key]
          return '' unless name.is_a?(Hash)

          (name[part] || '').to_s
        end

        def middle_initial(form, key)
          middle = name_part(form, key, 'middle')
          middle.empty? ? '' : middle[0].upcase
        end

        def combined_name(form, key)
          name = form.data[key]
          return '' unless name.is_a?(Hash)

          [name['last'], name['first'], name['middle']]
            .reject { |part| part.to_s.empty? }
            .join(', ')
        end

        # ---------- Addresses ----------

        def claimant_address_block(form)
          address_block(form.data['address'])
        end

        def facility_address_block(form)
          address_block(form.data['facility_address'])
        end

        def address_block(block)
          return (block || '').to_s unless block.is_a?(Hash)

          line1 = [block['street'], block['street2']].reject { |s| s.to_s.empty? }.join(' ')
          city_state_zip = [
            block['city'],
            block['state'],
            block['postal_code']
          ].reject { |s| s.to_s.empty? }.join(', ').sub(/, (\S+)\z/, ' \1')

          [line1, city_state_zip, block['country']].reject { |s| s.to_s.empty? }.join("\n")
        end

        def normalize_ssn(ssn)
          digits_only(ssn)
        end

        def digits_only(value)
          return '' if value.nil?

          value.to_s.gsub(/\D/, '')
        end

        def phone_digits(value)
          return '' if value.nil?
          return value.to_s.gsub(/\D/, '') unless value.is_a?(Hash)

          [value['area_code'], value['number']].compact.join.gsub(/\D/, '')
        end

        def format_iso_date(value)
          return '' if value.nil? || value.to_s.empty?

          if value.is_a?(Hash)
            month = value['month'].to_s
            day = value['day'].to_s
            year = value['year'].to_s
            return '' if month.empty? || day.empty? || year.empty?

            format('%<m>02d/%<d>02d/%<y>04d', m: month.to_i, d: day.to_i, y: year.to_i)
          else
            str = value.to_s

            parsed =
              if str.match?(%r{\A\d{2}/\d{2}/\d{4}\z})
                Date.strptime(str, '%m/%d/%Y')
              else
                Date.parse(str)
              end

            format('%<m>02d/%<d>02d/%<y>04d', m: parsed.month, d: parsed.day, y: parsed.year)
          end
        rescue ArgumentError, TypeError
          ''
        end
      end
      # rubocop:enable Metrics/ModuleLength
    end
  end
end
