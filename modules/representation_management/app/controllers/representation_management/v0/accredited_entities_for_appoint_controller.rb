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
        organizations = data.select { |record| record.is_a?(AccreditedOrganization) }
        acceptance_modes =
          RepresentationManagement::OrganizationWithAcceptanceMode.acceptance_modes_for(individuals)
        any_request_poas = any_request_poas_for(organizations)

        render json: data.map { |record| serialize_entity(record, acceptance_modes:, any_request_poas:) }
      end

      private

      def any_request_poas_for(organizations)
        return Set.new if organizations.empty?

        RepresentationManagement::AccreditedOrganizationWithAcceptanceCheck.any_request_poas_for(organizations)
      end

      def serialize_entity(record, acceptance_modes:, any_request_poas:)
        if record.is_a?(AccreditedIndividual)
          RepresentationManagement::AccreditedEntities::IndividualSerializer
            .new(record, { params: { acceptance_modes: } }).serializable_hash
        elsif record.is_a?(AccreditedOrganization)
          org = RepresentationManagement::AccreditedOrganizationWithAcceptanceCheck.new(record, any_request_poas:)
          RepresentationManagement::AccreditedEntities::OrganizationSerializer.new(org).serializable_hash
        end
      end

      def feature_enabled
        routing_error unless Flipper.enabled?(:arc_appoint_a_representative_use_accredited_models)
      end
    end
  end
end
