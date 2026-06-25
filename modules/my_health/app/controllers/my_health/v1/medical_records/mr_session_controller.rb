# frozen_string_literal: true

module MyHealth
  module V1
    module MedicalRecords
      ##
      # Controller for Medical Records session management.
      #
      # Establishes the upstream MR client session and reports PHR Manager
      # session status used to gate access to Medical Records data.
      #
      class MRSessionController < MRController
        ##
        # Establishes the Medical Records client session for the current user.
        #
        # @return [void] responds 204 No Content once the session is initialized
        #
        def create
          client
          head :no_content
        end

        ##
        # Returns the PHR Manager session status for the current user.
        #
        # @return [JSON] serialized PHR Manager status
        #
        def status
          resource = phrmgr_client.get_phrmgr_status
          render json: resource.to_json
        end
      end
    end
  end
end
