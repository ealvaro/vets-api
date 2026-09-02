# frozen_string_literal: true

require 'brd/brd'

module ClaimsApi
  module V3
    module DisabilityCompensation
      module Services
        class BrdLookup
          def initialize
            @brd = ClaimsApi::BRD.new
          end

          def active_classification_ids
            disabilities.pluck(:id)
          end

          def classification_end_date_for(id)
            entry = disabilities.find { |d| d[:id] == id }
            return nil if entry.nil? || entry[:endDateTime].nil?

            Date.parse(entry[:endDateTime])
          end

          private

          def disabilities
            @disabilities ||= @brd.disabilities
          end
        end
      end
    end
  end
end
