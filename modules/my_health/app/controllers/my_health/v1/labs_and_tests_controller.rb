# frozen_string_literal: true

module MyHealth
  module V1
    ##
    # Exposes a Veteran's lab results and diagnostic tests sourced from MHV or
    # the Accelerated Delivery (Oracle Health) data path.
    #
    class LabsAndTestsController < MRController
      ##
      # Lists the current user's labs and tests.
      #
      # @return [JSON] serialized list of labs and tests, or 202 if the patient is not found
      #
      def index
        render_resource client.list_labs_and_tests
      end

      ##
      # Retrieves a single diagnostic report by id.
      #
      # @return [JSON] serialized diagnostic report, or 202 if the patient is not found
      #
      def show
        record_id = params[:id].try(:to_i)
        render_resource client.get_diagnostic_report(record_id)
      end
    end
  end
end
