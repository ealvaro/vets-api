# frozen_string_literal: true

module MyHealth
  module V1
    module MedicalRecords
      ##
      # Controller for the Blue Button Medical Imaging (BBMI) notification
      # setting, indicating whether the user is notified when imaging is ready.
      #
      class BbmiNotificationController < MRController
        # Retrieves the BBMI notification setting
        # @return [JSON] BBMI notification setting
        def status
          resource = bb_client.get_bbmi_notification_setting
          render json: resource
        end
      end
    end
  end
end
