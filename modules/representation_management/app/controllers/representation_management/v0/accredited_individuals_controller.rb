# frozen_string_literal: true

module RepresentationManagement
  module V0
    class AccreditedIndividualsController < ApplicationController
      service_tag 'representation-management'
      skip_before_action :authenticate
      before_action :feature_enabled

      DEFAULT_PAGE = 1
      DEFAULT_PER_PAGE = 10

      def index
        search = RepresentationManagement::AccreditedIndividualSearch.new(
          search_params.merge({ model_class: AccreditedIndividual })
        )

        if search.valid?
          results = search.perform
          collection = Common::Collection.new(AccreditedIndividual, data: results)
          resource = collection.paginate(**pagination_params)
          acceptance_modes =
            RepresentationManagement::OrganizationWithAcceptanceMode.acceptance_modes_for(resource.data)
          options = { meta: resource.metadata, params: { acceptance_modes: } }

          render json: RepresentationManagement::AccreditedIndividuals::IndividualSerializer.new(resource.data, options)
        else
          render json: { errors: search.errors.full_messages }, status: :unprocessable_content
        end
      end

      private

      def search_params
        @search_params ||= begin
          params.require(%i[lat long type])
          params.permit(:distance, :lat, :long, :name, :org_name, :page, :per_page, :sort, :type)
        end
      end

      def pagination_params
        {
          page: search_params[:page] || DEFAULT_PAGE,
          per_page: search_params[:per_page] || DEFAULT_PER_PAGE
        }
      end

      def feature_enabled
        routing_error unless Flipper.enabled?(:arc_find_a_representative_backend_use_accredited_models)
      end
    end
  end
end
