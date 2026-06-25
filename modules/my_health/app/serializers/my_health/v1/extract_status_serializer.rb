# frozen_string_literal: true

module MyHealth
  module V1
    ##
    # JSONAPI serializer for the status of a Blue Button data extract, describing
    # the extract type, station, and timing/status of the most recent extract.
    #
    class ExtractStatusSerializer
      include JSONAPI::Serializer

      set_type :extract_status

      attributes :extract_type, :last_updated, :status, :created_on, :station_number
    end
  end
end
