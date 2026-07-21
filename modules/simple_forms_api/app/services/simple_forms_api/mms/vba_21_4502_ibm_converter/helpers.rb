# frozen_string_literal: true

module SimpleFormsApi
  module Mms
    module VBA214502IbmConverter
      module Helpers
        BRANCH_MAP = {
          'ARMY' => 'ARMY',
          'NAVY' => 'NAVY',
          'AIR FORCE' => 'AIR-FORCE',
          'MARINE CORPS' => 'MARINE',
          'COAST GUARD' => 'COAST-GUARD',
          'SPACE FORCE' => 'SPACE',
          'NOAA' => 'NOAA',
          'USPHS' => 'USPHS'
        }.freeze

        CONVEYANCE_MAP = {
          'AUTOMOBILE' => 'AUTO',
          'STATION WAGON' => 'STAT_WAGON',
          'VAN' => 'VAN',
          'TRUCK' => 'TRUCK'
        }.freeze

        def planned_address(form)
          planned = form.data['planned_mailing_address']
          if truthy?(form.data['active_duty']) && planned.is_a?(Hash) && planned.values.any? { |v| !v.to_s.empty? }
            planned
          else
            {}
          end
        end

        def current_address(form)
          form.data['current_mailing_address'] || {}
        end

        def normalize_ssn(ssn)
          return '' if ssn.nil?

          ssn.to_s.gsub(/\D/, '')
        end

        def domestic_phone(form)
          area = form.data.dig('phone_number', 'area_code').to_s
          num = form.data.dig('phone_number', 'number').to_s
          "#{area}#{num}".gsub(/\D/, '')
        end

        def international_phone(form)
          intl = form.data['international_phone_number']
          return '' if intl.nil? || !intl.is_a?(Hash)

          [intl['country_code'], intl['area_code'], intl['number']].compact.join.gsub(/\D/, '')
        end

        def normalize_zip(zip)
          return '' if zip.nil?

          zip.to_s.gsub(/\D/, '')[0, 5] || ''
        end

        def bool_to_checkbox(value)
          truthy?(value) ? 1 : 0
        end

        def yes_checkbox(value)
          truthy?(value) ? 1 : 0
        end

        def no_checkbox(value)
          return 0 if value.nil?

          truthy?(value) ? 0 : 1
        end

        def truthy?(value)
          return false if value.nil?
          return value if [true, false].include?(value)
          return true if value.to_s.match?(/\A(1|true|yes|y|t)\z/i)

          false
        end

        def branch_checkbox(form, target_suffix)
          branch_value = form.data['branch_of_service'].to_s.upcase
          mapped = BRANCH_MAP[branch_value]
          bool_to_checkbox(mapped == target_suffix)
        end

        def conveyance_checkbox(form, target_suffix)
          vehicle_type = form.data['vehicle_type'].to_s.upcase
          mapped = CONVEYANCE_MAP[vehicle_type]
          bool_to_checkbox(mapped == target_suffix)
        end

        def conveyance_other_checkbox(form)
          vehicle_type = form.data['vehicle_type'].to_s.upcase
          return 0 if vehicle_type.empty?

          bool_to_checkbox(!CONVEYANCE_MAP.key?(vehicle_type))
        end

        def conveyance_other_value(form)
          vehicle_type = form.data['vehicle_type'].to_s
          return '' if vehicle_type.empty?
          return '' if CONVEYANCE_MAP.key?(vehicle_type.upcase)

          vehicle_type
        end

        def date_parts_to_string(form, key)
          month = form.date_part(key, 'month').to_s
          day = form.date_part(key, 'day').to_s
          year = form.date_part(key, 'year').to_s
          return '' if month.empty? || day.empty? || year.empty?

          format('%<m>02d/%<d>02d/%<y>04d', m: month.to_i, d: day.to_i, y: year.to_i)
        rescue
          ''
        end
      end
    end
  end
end
