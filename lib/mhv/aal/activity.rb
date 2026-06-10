# frozen_string_literal: true

require 'vets/model'

module AAL
  ##
  # Model representing a single Account Activity Log entry from the MHV AAL API.
  # Maps to the ActivityDTO schema in the AAL OpenAPI specification.
  #
  class Activity
    include Vets::Model

    attribute :activity_id, Integer
    attribute :user_profile_id, Integer
    attribute :patient_id, Integer
    attribute :action, String
    attribute :status, String
    attribute :performer_type, String
    attribute :activity_type, String
    attribute :detail_value, String
    attribute :completion_time, String

    ##
    # Build an Activity from a camelCase hash returned by the MHV API.
    #
    # @param attrs [Hash] A single activity record from the API response
    # @return [AAL::Activity]
    #
    def self.from_api(attrs)
      new(
        activity_id: attrs['activityId'],
        user_profile_id: attrs['userProfileId'],
        patient_id: attrs['patientId'],
        action: attrs['action'],
        status: attrs['status'],
        performer_type: attrs['performerType'],
        activity_type: attrs['activityType'],
        detail_value: attrs['detailValue'],
        completion_time: attrs['completionTime']
      )
    end

    ##
    # Provide a stable identifier for JSONAPI serialization.
    #
    def id
      activity_id
    end
  end
end
