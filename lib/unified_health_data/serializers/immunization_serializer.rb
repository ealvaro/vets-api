# frozen_string_literal: true

module UnifiedHealthData
  module Serializers
    class ImmunizationSerializer
      include JSONAPI::Serializer

      set_id :id
      set_type :immunization

      attributes :cvx_code,
                 :date,
                 :dose_number,
                 :dose_series,
                 :group_name,
                 :location,
                 :provider,
                 :manufacturer,
                 :note,
                 :reaction,
                 :short_description,
                 :administration_site,
                 :lot_number,
                 :status
    end
  end
end
