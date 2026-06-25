# frozen_string_literal: true

module Mobile
  module V0
    ##
    # Mobile (v0) controller for a Veteran's immunization records, sourced from
    # the Lighthouse Health service and adapted to the mobile response shape.
    #
    class ImmunizationsController < ApplicationController
      service_tag 'mhv-medical-records'

      ##
      # Lists the current user's immunizations.
      #
      # @return [JSON] serialized immunizations
      #
      def index
        render json: Mobile::V0::ImmunizationSerializer.new(immunizations_adapter.parse(service.get_immunizations))
      end

      private

      def immunizations_adapter
        Mobile::V0::Adapters::Immunizations.new
      end

      def service
        Mobile::V0::LighthouseHealth::Service.new(@current_user)
      end
    end
  end
end
