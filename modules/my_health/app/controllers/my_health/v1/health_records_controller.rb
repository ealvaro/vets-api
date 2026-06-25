# frozen_string_literal: true

module MyHealth
  module V1
    ##
    # Exposes Blue Button health record operations: extract status, eligible
    # data classes, and on-demand report generation.
    #
    class HealthRecordsController < BBController
      ##
      # Returns the status of the most recent Blue Button data extract.
      #
      # @return [JSON] serialized extract status with metadata
      #
      def refresh
        resource = client.get_extract_status

        render json: ExtractStatusSerializer.new(resource.data, { meta: resource.metadata })
      end

      ##
      # Returns the data classes the current user is eligible to include in a
      # Blue Button report.
      #
      # @return [JSON] serialized eligible data classes with metadata
      #
      def eligible_data_classes
        resource = client.get_eligible_data_classes

        render json: EligibleDataClassesSerializer.new(resource.data, { meta: resource.metadata })
      end

      ##
      # Requests generation of a Blue Button report for the given date range and
      # data classes.
      #
      # @return [void] responds 202 Accepted once generation is queued
      #
      def create
        client.post_generate(params.permit(:from_date, :to_date, data_classes: []))

        head :accepted
      end
    end
  end
end
