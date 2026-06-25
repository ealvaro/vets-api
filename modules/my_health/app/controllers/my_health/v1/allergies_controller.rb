# frozen_string_literal: true

module MyHealth
  module V1
    ##
    # Exposes a Veteran's allergy and intolerance records sourced from MHV or
    # the Accelerated Delivery (Oracle Health) data path.
    #
    class AllergiesController < MRController
      ##
      # Lists the current user's allergy records.
      #
      # @return [JSON] serialized list of allergies, or 202 if the patient is not found
      #
      def index
        render_resource client.list_allergies
      end

      ##
      # Retrieves a single allergy record by id.
      #
      # @return [JSON] serialized allergy, or 202 if the patient is not found
      #
      def show
        allergy_id = params[:id].try(:strip)
        render_resource client.get_allergy(allergy_id)
      end
    end
  end
end
