# frozen_string_literal: true

require 'unique_user_events'

module MyHealth
  module V1
    ##
    # Exposes a Veteran's vital signs sourced from MHV or the Accelerated
    # Delivery (Oracle Health) data path.
    #
    class VitalsController < MRController
      ##
      # Lists the current user's vital signs within an optional date range and
      # logs unique-user access events for medical records and vitals.
      #
      # @return [JSON] serialized list of vitals, or 202 if the patient is not found
      #
      def index
        resource = client.list_vitals(params[:from], params[:to])

        # Log unique user events for vitals accessed
        UniqueUserEvents.log_events(
          user: current_user,
          event_names: [
            UniqueUserEvents::EventRegistry::MEDICAL_RECORDS_ACCESSED,
            UniqueUserEvents::EventRegistry::MEDICAL_RECORDS_VITALS_ACCESSED
          ]
        )

        render_resource resource
      end
    end
  end
end
