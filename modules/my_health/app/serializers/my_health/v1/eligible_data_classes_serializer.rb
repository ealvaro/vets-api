# frozen_string_literal: true

module MyHealth
  module V1
    ##
    # JSONAPI serializer for the data classes a user is eligible to include in a
    # Blue Button report. Serializes the collection into a single resource whose
    # +data_classes+ attribute is the list of class names.
    #
    class EligibleDataClassesSerializer
      include JSONAPI::Serializer

      set_type :eligible_data_classes
      set_id { '' }

      attribute :data_classes do |object|
        object.map(&:name)
      end
    end
  end
end
