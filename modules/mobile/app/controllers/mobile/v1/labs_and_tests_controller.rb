# frozen_string_literal: true

require 'unified_health_data/medical_records_service'
require 'unified_health_data/serializers/lab_or_test_serializer'
require 'unique_user_events'

module Mobile
  module V1
    ##
    # Mobile (v1) controller for a Veteran's lab and test results served through
    # the Unified Health Data (UHD) Medical Records service.
    #
    # Gated behind the +:mhv_accelerated_delivery_uhd_enabled+ feature flag.
    # Supports date-range filtering; SCDF warnings are not surfaced to the mobile
    # app.
    #
    class LabsAndTestsController < ApplicationController
      include MedicalRecords::ErrorHandler
      include Mobile::AALClientConcerns

      service_tag :'mhv-medical-records'

      before_action :controller_enabled?

      ##
      # Lists the current user's labs and tests within an optional date range
      # and logs unique-user access events.
      #
      # @return [JSON] serialized labs and tests
      #
      def index
        start_date = params[:startDate]
        end_date = params[:endDate]
        result = service.get_labs(start_date:, end_date:, caller: 'mobile_v1')
        labs = result[:records]

        log_labs_user_events
        log_mhv_aal(Mobile::AALClientConcerns::ActivityTypes::LAB_AND_TEST_RESULTS)

        render json: UnifiedHealthData::Serializers::LabOrTestSerializer.new(labs)
      rescue Common::Exceptions::GatewayTimeout,
             Common::Client::Errors::ClientError,
             Common::Exceptions::BackendServiceException,
             StandardError => e
        handle_error(e, resource_name: 'Mobile labs and tests', api_type: 'Mobile UHD')
      end

      private

      def log_labs_user_events
        UniqueUserEvents.log_events(
          user: @current_user,
          event_names: [
            UniqueUserEvents::EventRegistry::MEDICAL_RECORDS_ACCESSED,
            UniqueUserEvents::EventRegistry::MEDICAL_RECORDS_LABS_ACCESSED
          ]
        )
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
