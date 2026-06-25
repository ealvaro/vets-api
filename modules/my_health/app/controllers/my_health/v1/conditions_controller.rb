# frozen_string_literal: true

module MyHealth
  module V1
    ##
    # Exposes a Veteran's health conditions sourced from MHV or the Accelerated
    # Delivery (Oracle Health) data path.
    #
    class ConditionsController < MRController
      ##
      # Lists the current user's health conditions.
      #
      # @return [JSON] serialized list of conditions, or 202 if the patient is not found
      #
      def index
        render_resource client.list_conditions
      end

      ##
      # Retrieves a single health condition by id.
      #
      # @return [JSON] serialized condition, or 202 if the patient is not found
      #
      def show
        condition_id = params[:id].try(:to_i)
        render_resource client.get_condition(condition_id)
      end
    end
  end
end
