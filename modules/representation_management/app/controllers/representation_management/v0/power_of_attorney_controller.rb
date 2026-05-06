# frozen_string_literal: true

require 'lighthouse/benefits_claims/service'

module RepresentationManagement
  module V0
    class PowerOfAttorneyController < ApplicationController
      service_tag 'representation-management'
      before_action { authorize :power_of_attorney, :access? }

      STATSD_KEY_PREFIX = 'api.representation_management.power_of_attorney'

      def index
        log_request_attempt if participant_id_missing?

        begin
          @active_poa = lighthouse_service.get_power_of_attorney
        rescue => e
          log_request_failure(e) if participant_id_missing?
          raise
        end

        if @active_poa.blank? || record.blank?
          render json: { data: {} }, status: :ok
        else
          render json: serializer.new(record), status: :ok
        end
      end

      private

      def lighthouse_service
        BenefitsClaims::Service.new(icn)
      end

      def icn
        @current_user&.icn
      end

      def participant_id_missing?
        @participant_id_missing ||= @current_user&.participant_id.blank?
      end

      def poa_code
        @poa_code ||= @active_poa.dig('data', 'attributes', 'code')
      end

      def poa_type
        @poa_type ||= @active_poa.dig('data', 'type')
      end

      def record
        return @record if defined? @record

        @record ||= if poa_type == 'organization'
                      organization
                    else
                      representative
                    end
      end

      def serializer
        if poa_type == 'organization'
          RepresentationManagement::PowerOfAttorney::OrganizationSerializer
        else
          RepresentationManagement::PowerOfAttorney::RepresentativeSerializer
        end
      end

      def organization
        Veteran::Service::Organization.find_by(poa: poa_code)
      end

      def representative
        Veteran::Service::Representative.where('? = ANY(poa_codes)', poa_code).order(created_at: :desc).first
      end

      # Custom metrics and logging for "no participant id for user" scenario
      def log_request_attempt
        StatsD.increment("#{STATSD_KEY_PREFIX}.#{action_name}.no_participant_id.total")
        Rails.logger.info('Fetching POA status, no Participant ID in MPI profile')
      end

      def log_request_failure(error)
        StatsD.increment("#{STATSD_KEY_PREFIX}.#{action_name}.no_participant_id.failure")
        Rails.logger.error("Failed to fetch POA status, no Participant ID: #{error.class}")
      end
    end
  end
end
