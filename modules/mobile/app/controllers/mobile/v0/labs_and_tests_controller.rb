# frozen_string_literal: true

require 'lighthouse/veterans_health/client'

module Mobile
  module V0
    ##
    # Mobile (v0) controller for a Veteran's lab and test results (diagnostic
    # reports), sourced from the Lighthouse Veterans Health API and parsed from
    # the FHIR bundle.
    #
    class LabsAndTestsController < ApplicationController
      include Mobile::AALClientConcerns

      service_tag 'mhv-medical-records'

      ##
      # Lists the current user's diagnostic reports.
      #
      # @return [JSON] serialized diagnostic reports
      #
      def index
        response = client.list_diagnostic_reports(params)
        body = response.body
        validate_response_schema(body, 'lighthouse_list_diagnostic_reports')
        diagnostic_reports = body['entry'].map do |entry|
          Mobile::V0::Adapters::DiagnosticReport.new.parse(entry['resource'])
        end

        log_mhv_aal(Mobile::AALClientConcerns::ActivityTypes::LAB_AND_TEST_RESULTS)

        render json: DiagnosticReportsSerializer.new(diagnostic_reports)
      end

      private

      def client
        @client ||= Lighthouse::VeteransHealth::Client.new(current_user.icn)
      end

      def validate_response_schema(body, contract_name)
        # check for successful response structure
        return if !body.is_a?(Hash) || body['resourceType'] != 'Bundle'

        SchemaContract::ValidationInitiator.call_with_body(
          user: current_user, body:, contract_name:
        )
      end
    end
  end
end
