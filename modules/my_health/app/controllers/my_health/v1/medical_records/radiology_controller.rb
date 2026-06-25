# frozen_string_literal: true

module MyHealth
  module V1
    module MedicalRecords
      ##
      # Controller for retrieving a Veteran's radiology reports via the Blue
      # Button client.
      #
      class RadiologyController < MRController
        ##
        # Lists the current user's radiology reports.
        #
        # @return [JSON] serialized list of radiology reports
        #
        def index
          resource = bb_client.list_radiology
          render json: resource.to_json
        end
      end
    end
  end
end
