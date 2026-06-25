# frozen_string_literal: true

module Mobile
  module V0
    ##
    # JSONAPI serializer for a Veteran's allergy intolerance records in the
    # mobile (v0) response shape, exposing FHIR-derived attributes such as
    # clinical status, code, reactions, and category.
    #
    class AllergyIntoleranceSerializer
      include JSONAPI::Serializer

      set_type :allergy_intolerance

      attributes :resourceType,
                 :type,
                 :clinicalStatus,
                 :code,
                 :recordedDate,
                 :patient,
                 :notes,
                 :recorder,
                 :reactions,
                 :category
    end
  end
end
