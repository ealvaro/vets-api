# frozen_string_literal: true

module RepresentationManagement
  module V0
    class AccreditedEntitiesForAppointController < ApplicationController
      service_tag 'representation-management'
      skip_before_action :authenticate
      before_action :feature_enabled

      def index
        data = RepresentationManagement::AccreditedEntityQuery.new(params[:query]).results

        individuals = data.select { |record| record.is_a?(AccreditedIndividual) }
        acceptance_modes =
          RepresentationManagement::OrganizationWithAcceptanceMode.acceptance_modes_for(individuals)
        serializer_options = { params: { acceptance_modes: } }

        json_response = data.map do |record|
          if record.is_a?(AccreditedIndividual)
            RepresentationManagement::AccreditedEntities::IndividualSerializer
              .new(record, serializer_options).serializable_hash
          elsif record.is_a?(AccreditedOrganization)
            RepresentationManagement::AccreditedIndividuals::OrganizationSerializer.new(record).serializable_hash
          end
        end

        render json: json_response
      end

      private

      def feature_enabled
        routing_error unless Flipper.enabled?(:arc_appoint_a_representative_use_accredited_models)
      end
    end
  end
end
