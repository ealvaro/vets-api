# frozen_string_literal: true

module Mobile
  module V0
    ##
    # Mobile (v0) controller for a Veteran's immunization records, sourced from
    # the Lighthouse Health service and adapted to the mobile response shape.
    #
    class ImmunizationsController < ApplicationController
      include Mobile::AALClientConcerns

      service_tag 'mhv-medical-records'

      ##
      # Lists the current user's immunizations.
      #
      # @return [JSON] serialized immunizations
      #
      def index
        body = service.get_immunizations
        validate_response_schema(@current_user, body, 'lighthouse_get_immunizations')
        log_mhv_aal(Mobile::AALClientConcerns::ActivityTypes::VACCINES)
        render json: Mobile::V0::ImmunizationSerializer.new(immunizations_adapter.parse(body))
      end

      private

      def immunizations_adapter
        Mobile::V0::Adapters::Immunizations.new
      end

      def service
        Mobile::V0::LighthouseHealth::Service.new(@current_user)
      end

      def validate_response_schema(user, body, contract_name)
        # check for successful response structure
        return if !body.is_a?(Hash) || body[:resource_type] != 'Bundle'

        SchemaContract::ValidationInitiator.call_with_body(
          user:, body:, contract_name:
        )
      end
    end
  end
end
