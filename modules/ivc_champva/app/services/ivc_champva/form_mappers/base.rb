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
        IvcChampva::PdfAddressFormatter.format(str)
      end

      def gender_radio(val)
        case val
        when 'male' then 0
        when 'female' then 1
        end
      end
    end
  end
end
