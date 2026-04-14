# frozen_string_literal: true

module VAOS
  module V2
    module Unified
      class BaseSlot
        attr_accessor :id, :start, :end, :provider_id, :provider_type, :provider_service_id

        def initialize(attrs = {})
          attrs.each { |key, value| send(:"#{key}=", value) if respond_to?(:"#{key}=") }
        end
      end
    end
  end
end
