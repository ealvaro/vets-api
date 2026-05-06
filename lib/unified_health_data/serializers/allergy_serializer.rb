# frozen_string_literal: true

module UnifiedHealthData
  module Serializers
    class AllergySerializer
      include JSONAPI::Serializer

      set_id :id
      set_type :allergy

      attributes :id,
                 :name,
                 :date,
                 :categories,
                 :reactions,
                 :location,
                 :observedHistoric, # 'o' or 'h' - only on VistA data
                 :notes,
                 :provider
    end
  end
end
