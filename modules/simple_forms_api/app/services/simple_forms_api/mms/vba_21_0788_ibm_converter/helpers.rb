# frozen_string_literal: true

module SimpleFormsApi
  module Mms
    module VBA210788IbmConverter
      module Helpers # rubocop:disable Metrics/ModuleLength
        def relationship_checkbox_fields(form)
          relationship = form.data['relationship'].to_s

          RELATIONSHIP_CHECKBOXES.transform_values do |value|
            relationship == value ? 1 : 0
          end
        end

        def other_relationship(form)
          return '' unless form.data['relationship'].to_s == 'other'

          # TODO: confirm key for the free-text "other" relationship value.
          (form.data['other_relationship'] || form.data['relationship_other'] || '').to_s
        end

        def apportionee_fields(entry, index)
          receipt = tri_state(entry['currently_in_receipt'])

          {
            "NAME_APPORTIONMENT_REQUESTED_#{index}" => apportionee_name(entry),
            "APPORTION_SSN_#{index}" => normalize_ssn(entry['ssn']),
            "APPORTION_RELATIONSHIP_TO_VETERAN_#{index}" => entry['relationship_to_veteran'] || '',
            "APPORTION_CURRENTLY_IN RECEPIENT_YES_#{index}" => receipt == :yes ? 1 : 0,
            "APPORTION_CURRENTLY_IN RECEPIENT_NO_#{index}" => receipt == :no ? 1 : 0
          }
        end

        def apportionee_name(entry)
          name = entry['full_name']
          return (entry['name'] || '').to_s unless name.is_a?(Hash)

          [name['last'], name['first'], name['middle']]
            .reject { |part| part.to_s.empty? }
            .join(', ')
        end

        def stepchild_yes_no_fields(form)
          in_household = tri_state(form.data['stepchild_living_in_household'])
          adopted = tri_state(form.data['legally_adopted'])

          {
            'VETERAN_STEP_CHILD_YES' => in_household == :yes ? 1 : 0,
            'VETERAN_STEP_CHILD_NO' => in_household == :no ? 1 : 0,
            'VETERAN_STEP_CHILD_ADOPTED_YES' => adopted == :yes ? 1 : 0,
            'VETERAN_STEP_CHILD_ADOPTED_NO' => adopted == :no ? 1 : 0
          }
        end

        def reason_checkbox_fields(form)
          reason = form.data['apportionment_reason'].to_s

          REASON_CHECKBOXES.transform_values { |value| reason == value ? 1 : 0 }
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

        def signature_checkbox(form)
          sig = form.data['claimant_signature'] || form.data['statement_of_truth_signature']
          return 0 if sig.nil? || sig.to_s.strip.empty?

          1
        end

        def tri_state(value)
          return :unset if value.nil? || value.to_s.strip.empty?
          return :yes if value == true || value.to_s.match?(/\A(1|true|yes|y|t)\z/i)
          return :no if value == false || value.to_s.match?(/\A(0|false|no|n|f)\z/i)

          :unset
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
            parsed = Date.parse(value.to_s)
            format('%<m>02d/%<d>02d/%<y>04d', m: parsed.month, d: parsed.day, y: parsed.year)
          end
        rescue ArgumentError, TypeError
          ''
        end
      end # rubocop:enable Metrics/ModuleLength
    end
  end
end
