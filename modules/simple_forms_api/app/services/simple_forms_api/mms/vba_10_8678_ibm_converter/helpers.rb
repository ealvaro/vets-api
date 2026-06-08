# frozen_string_literal: true

# rubocop:disable Metrics/ModuleLength
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

        def appliance_fields(appliance, index)
          approved = approved_state(appliance['va_approved'])

          {
            "NAME_APPLIANCE_#{index}" => appliance['device_or_medication'] || '',
            "DISABILITY_APPLIANCE_#{index}" => appliance['service_connected_disability'] || '',
            "ISSUE_DATE_APPLIANCE_#{index}" => issue_date(appliance['issue_date']),
            "ISSUE_OFFICE_NAME_LOC_APPLIANCE_#{index}" => appliance['issuing_facility'] || '',
            "IMPACTED_LOC_APPLIANCE_#{index}" => format_impacted_locations(appliance['impacted_locations']),
            "VA_APPROVED_YES_APPLIANCE_#{index}" => approved == :yes ? 1 : 0,
            "VA_APPROVED_NO_APPLIANCE_#{index}" => approved == :no ? 1 : 0
          }
        end

        def approved_state(value)
          return :unset if value.nil? || value.to_s.strip.empty?
          return :yes if value == true || value.to_s.match?(/\A(1|true|yes|y|t)\z/i)
          return :no if value == false || value.to_s.match?(/\A(0|false|no|n|f)\z/i)

          :unset
        end

        def format_impacted_locations(value)
          return '' if value.nil? || !value.is_a?(Hash)

          IMPACTED_LOCATION_LABELS.each_with_object([]) do |(key, label), acc|
            acc << label if truthy?(value[key])
          end.join(', ')
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

        def normalize_ssn(ssn)
          return '' if ssn.nil?

          ssn.to_s.gsub(/\D/, '')
        end

        def phone_digits(value)
          return '' if value.nil?
          return value.to_s.gsub(/\D/, '') unless value.is_a?(Hash)

          [value['area_code'], value['number']].compact.join.gsub(/\D/, '')
        end

        def bool_to_checkbox(value)
          truthy?(value) ? 1 : 0
        end

        def truthy?(value)
          return false if value.nil?
          return value if [true, false].include?(value)
          return true if value.to_s.match?(/\A(1|true|yes|y|t)\z/i)

          false
        end

        def signature_checkbox(form)
          sig = form.data['veteran_signature'] || form.data['statement_of_truth_signature']
          return 0 if sig.nil? || sig.to_s.strip.empty?

          1
        end

        def allowance_value(form, key)
          block = form.data['clothing_allowance']
          return '' unless block.is_a?(Hash)

          (block[key] || '').to_s
        end

        def app_calendar_year(form)
          explicit = form.data['app_calendar_year']
          return explicit.to_s unless explicit.nil? || explicit.to_s.empty?

          sig_date = form.data['signature_date']
          return '' if sig_date.nil? || sig_date.to_s.empty?

          Date.parse(sig_date.to_s).year.to_s
        rescue ArgumentError, TypeError
          ''
        end

        def issue_date(value)
          return '' if value.nil? || value.to_s.empty?

          if value.is_a?(Hash)
            month = value['month'].to_s
            year = value['year'].to_s
            return '' if month.empty? || year.empty?

            format('%<m>02d/%<y>04d', m: month.to_i, y: year.to_i)
          else
            parsed = Date.parse(value.to_s)
            format('%<m>02d/%<y>04d', m: parsed.month, y: parsed.year)
          end
        rescue ArgumentError, TypeError
          ''
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
# rubocop:enable Metrics/ModuleLength
