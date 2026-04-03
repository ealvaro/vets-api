# frozen_string_literal: true

module MyHealth
  module V1
    class EhrCrosswalkController < SMController
      def index
        entries = client.get_crosswalk
        resource = entries.map { |entry| OpenStruct.new(entry) }
        render json: EhrCrosswalkSerializer.new(resource)
      end
    end
  end
end
