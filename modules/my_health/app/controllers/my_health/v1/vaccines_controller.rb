# frozen_string_literal: true

module MyHealth
  module V1
    ##
    # Exposes a Veteran's vaccination records sourced from MHV or the Accelerated
    # Delivery (Oracle Health) data path.
    #
    class VaccinesController < MRController
      ##
      # Lists the current user's vaccine records.
      #
      # @return [JSON] serialized list of vaccines, or 202 if the patient is not found
      #
      def index
        render_resource client.list_vaccines
      end

      ##
      # Retrieves a single vaccine record by id.
      #
      # @return [JSON] serialized vaccine, or 202 if the patient is not found
      #
      def show
        vaccine_id = params[:id].try(:to_i)
        render_resource client.get_vaccine(vaccine_id)
      end
    end
  end
end
