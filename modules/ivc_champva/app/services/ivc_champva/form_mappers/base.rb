# frozen_string_literal: true

module IvcChampva
  module FormMappers
    module Base
      def truthy?(val)
        [true, 'true'].include?(val)
      end

      def name_with_suffix(last, suffix)
        [last, suffix].compact.join(' ')
      end

      def middle_initial(middle)
        middle&.first
      end

      def format_address_string(str)
        str&.split(/\n/)&.join('\n')
      end

      def gender_radio(val)
        case val
        when 'male' then 0
        when 'female' then 1
        end
      end

      # A field may be a flat String value, or a Hash nesting the value under `subkey`.
      # Backwards compatible during FE/BE nested-data-structure rollout.
      def extract_flat_or_nested(field, subkey)
        return nil if field.nil?

        field.is_a?(Hash) ? field[subkey] : field
      end
    end
  end
end
