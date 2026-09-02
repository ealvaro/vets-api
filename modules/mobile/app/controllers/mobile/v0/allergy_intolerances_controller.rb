# frozen_string_literal: true

require 'lighthouse/veterans_health/client'
require 'unique_user_events'

module Mobile
  module V0
    ##
    # Mobile (v0) controller for a Veteran's allergy and intolerance records,
    # sourced from the Lighthouse Veterans Health API. Parses the FHIR bundle
    # with either the current or legacy adapter based on a feature flag.
    #
    class AllergyIntolerancesController < ApplicationController
      include Mobile::AALClientConcerns

      service_tag 'mhv-medical-records'

      ##
      # Lists the current user's allergy intolerances and logs unique-user
      # access events.
      #
      # @return [JSON] serialized allergy intolerances
      #
      def index
        response = client.list_allergy_intolerances
        allergy_intolerances = if Flipper.enabled?(:mobile_allergy_intolerance_model, @current_user)
                                 Mobile::V0::Adapters::AllergyIntolerance.new.parse(response.body['entry'])
                               else
                                 Mobile::V0::Adapters::LegacyAllergyIntolerance.new.parse(response.body['entry'])
                               end

        # Log unique user events for allergies accessed
        UniqueUserEvents.log_events(
          user: @current_user,
          event_names: [
            UniqueUserEvents::EventRegistry::MEDICAL_RECORDS_ACCESSED,
            UniqueUserEvents::EventRegistry::MEDICAL_RECORDS_ALLERGIES_ACCESSED
          ]
        )

        log_mhv_aal(Mobile::AALClientConcerns::ActivityTypes::ALLERGY_AND_REACTIONS)

        render json: AllergyIntoleranceSerializer.new(allergy_intolerances)
      end

      private

      def client
        @client ||= Lighthouse::VeteransHealth::Client.new(current_user.icn)
      end
    end
  end
end
