# frozen_string_literal: true

module SimpleFormsApi
  module Mms
    module VBA108678IbmConverter
      module Helpers
        IMPACTED_LOCATION_LABELS = {
          'upper_left' => 'Upper Left',
          'upper_right' => 'Upper Right',
          'lower_left' => 'Lower Left',
          'lower_right' => 'Lower Right'
        }.freeze
        TABLE_ROWS = 4

        def handle_device_mappings(appliances)
          result = {}

          TABLE_ROWS.times do |i|
            n = i + 1
            appliance = appliances&.dig(i)

            result["DISABILITY_#{n}"] = appliance&.dig(:disability) || ''
            result["NAME_APPLIANCE_#{n}"] = appliance&.dig(:device) || ''

            locations = appliance&.dig(:impacted_locations)

            upper_left  = locations&.dig(:upper_left)
            upper_right = locations&.dig(:upper_right)
            lower_left  = locations&.dig(:lower_left)
            lower_right = locations&.dig(:lower_right)

            result["IMPACTED_LOC_UPPER_LEFT_APPLIANCE_#{n}"]  = upper_left ? '1' : '0'
            result["IMPACTED_LOC_UPPER_RIGHT_APPLIANCE_#{n}"] = upper_right ? '1' : '0'
            result["IMPACTED_LOC_UPPER_APPLIANCE_#{n}"]       = upper_left || upper_right ? '1' : '0'
            result["IMPACTED_LOC_LOWER_LEFT_APPLIANCE_#{n}"]  = lower_left ? '1' : '0'
            result["IMPACTED_LOC_LOWER_RIGHT_APPLIANCE_#{n}"] = lower_right ? '1' : '0'
            result["IMPACTED_LOC_LOWER_APPLIANCE_#{n}"]       = lower_left || lower_right ? '1' : '0'
          end

          result
        end

        def full_name(form)
          name = form.data['full_name']
          return (form.data['veteran_name'] || '').to_s unless name.is_a?(Hash)

          last = name['last'] || ''
          first = name['first'] || ''
          middle = name['middle'] || ''
          # Per dictionary: "LAST NAME, FIRST NAME, MIDDLE NAME OF VETERAN"
          [last, first, middle].reject { |part| part.to_s.empty? }.join(', ')
        end

        def veteran_address_block(form)
          block = form.data['address']
          return '' unless block.is_a?(Hash)

          line1 = [block['street'], block['street2']].reject { |s| s.to_s.empty? }.join(' ')
          city_state_zip = [
            block['city'],
            block['state'],
            block['postal_code']
          ].reject { |s| s.to_s.empty? }.join(', ').sub(/, (\S+)\z/, ' \1')

          [line1, city_state_zip, block['country']].reject { |s| s.to_s.empty? }.join("\n")
        end

        def normalize_last_4_ssn(ssn)
          return '' if ssn.nil?

          ssn.to_s.gsub(/\D/, '')[-4..]
        end

        def phone_digits(value)
          return '' if value.nil?
          return value.to_s.gsub(/\D/, '') unless value.is_a?(Hash)

          [value['area_code'], value['number']].compact.join.gsub(/\D/, '')
        end

        def signature_checkbox(form)
          sig = form.data['veteran_signature'] || form.data['statement_of_truth_signature']
          return 0 if sig.nil? || sig.to_s.strip.empty?

          1
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
      end
    end
  end
end
