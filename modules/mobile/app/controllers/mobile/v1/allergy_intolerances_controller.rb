# frozen_string_literal: true

require 'unified_health_data/medical_records_service'
require 'unified_health_data/serializers/allergy_serializer'

module Mobile
  module V1
    ##
    # Mobile (v1) controller for a Veteran's allergy records served through the
    # Unified Health Data (UHD) Medical Records service.
    #
    # Gated behind the +:mhv_accelerated_delivery_uhd_enabled+ and
    # +:mhv_accelerated_delivery_allergies_enabled+ feature flags. Paginates
    # results; SCDF partial-failure warnings are not surfaced to the mobile app.
    #
    class AllergyIntolerancesController < ApplicationController
      service_tag 'mhv-medical-records'

      before_action :controller_enabled?
      before_action :validate_feature_flag

      ##
      # Lists the current user's allergies, paginated.
      #
      # @return [JSON] serialized, paginated allergies
      #
      def index
        result = service.get_allergies
        # Warnings (e.g., Partial Failure responses from SCDF) are not surfaced to the mobile app.
        # Mobile has its own release cycle; warning support can be added separately if needed.
        # For now, just grab the records and return them
        paged, page_meta = paginate_allergies(result[:records])
        serialized_allergies = UnifiedHealthData::Serializers::AllergySerializer.new(paged, page_meta)
        render json: serialized_allergies,
               status: :ok
      rescue Common::Exceptions::BackendServiceException => e
        Rails.logger.error("Caught BackendServiceException: #{e.message}")
        raise Common::Exceptions::BackendServiceException, 'MOBL_502_upstream_error'
      rescue => e
        Rails.logger.error("Caught unexpected error: #{e.class}, #{e.message}")
        raise e
      end

      private

      def validate_feature_flag
        return if Flipper.enabled?(:mhv_accelerated_delivery_allergies_enabled, @current_user)

        render json: {
          error: {
            code: 'FEATURE_NOT_AVAILABLE',
            message: 'This feature is not currently available'
          }
        }, status: :forbidden
      end

      def pagination_contract
        Mobile::V0::Contracts::PaginationBase.new.call(
          page_number: params.dig(:page, :number),
          page_size: params.dig(:page, :size)
        )
      end

      def paginate_allergies(list)
        Mobile::PaginationHelper.paginate(list:, validated_params: pagination_contract)
      end

      def controller_enabled?
        routing_error unless Flipper.enabled?(:mhv_accelerated_delivery_uhd_enabled, @current_user)
      end

      def routing_error
        raise Common::Exceptions::RoutingError, params[:path]
      end

      def service
        UnifiedHealthData::MedicalRecordsService.new(@current_user)
      end
    end
  end
end
