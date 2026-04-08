# frozen_string_literal: true

module VAOS
  module V2
    module Unified
      class BaseProvider
        attr_accessor :id, :name, :facility_name, :address, :phone, :latitude, :longitude,
                      :provider_type, :distance_from_user

        def initialize(attrs = {})
          attrs.each { |key, value| send(:"#{key}=", value) if respond_to?(:"#{key}=") }
        end

        def formatted_address
          return nil if address.blank?

          parts = [
            address[:street1], address[:street2], address[:street3],
            address[:city], address[:state], address[:zip]
          ].compact
          parts.join(', ')
        end
      end
    end
  end
end
