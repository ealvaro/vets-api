# frozen_string_literal: true

module Mobile
  module V0
    module Concerns
      module AllergyDateResolvable
        extend ActiveSupport::Concern

        private

        # Returns the recordedDate, falling back to onsetDateTime if recordedDate is not present.
        def resolve_date(allergy_info)
          date_value = allergy_info&.dig('recordedDate').presence
          if date_value.blank?
            date_value = allergy_info&.dig('onsetDateTime').presence
            StatsD.increment('mobile.allergy.replace_date_with_onset') if date_value.present?
          end
          date_value
        end
      end
    end
  end
end
