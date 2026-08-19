# frozen_string_literal: true

module MyHealth
  module V1
    module MedicalRecords
      ##
      # Controller for patient demographics and treatment-facility data sourced
      # from the Blue Button client.
      #
      class PatientController < MRController
        ##
        # Keys from the upstream MHV patient resource that the frontend account
        # summary consumes. All other top-level keys (userProfile, icn,
        # patientRegistryChanges, correlation metadata, etc.) contain sensitive or
        # unused data and must not be transmitted to the browser.
        PATIENT_ALLOWED_KEYS = %w[facilities ipas].freeze

        # Gets a user's treatment facilities
        # @return [Array] of treatment facilities and related user info
        def index
          resource = bb_client.get_patient
          render json: resource.slice(*PATIENT_ALLOWED_KEYS).to_json
        end

        ##
        # Gets the current user's demographic information.
        #
        # @return [JSON] serialized patient demographic info
        #
        def demographic
          resource = bb_client.get_demographic_info
          render json: resource.to_json
        end
      end
    end
  end
end
