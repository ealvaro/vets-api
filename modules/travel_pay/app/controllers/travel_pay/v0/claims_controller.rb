# frozen_string_literal: true

module TravelPay
  module V0
    class ClaimsController < ApplicationController
      include AppointmentHelper
      include ClaimHelper
      include ErrorHandling

      after_action :scrub_logs, only: [:show]
      before_action :check_smoc_feature_flag, only: [:create]

      def index
        claims = claims_service.get_claims_by_date_range(params)
        monitor.track_request(:info, 'Claims index success', 'travel_pay.claims.index',
                              tags: ['result:success'])
        render json: claims, status: claims[:metadata]['status']
      rescue => e
        monitor.track_request(:warn, 'Claims index failure', 'travel_pay.claims.index',
                              error: e.message, tags: ['result:failure'])
        raise
      end

      def show
        unless Flipper.enabled?(:travel_pay_view_claim_details, @current_user)
          message = 'Travel Pay Claim Details unavailable per feature toggle'
          raise Common::Exceptions::ServiceUnavailable, message:
        end

        claim = fetch_claim_details(params[:id])
        return if performed?

        if claim.nil?
          raise Common::Exceptions::ResourceNotFound.new(detail: "Claim not found. ID provided: #{params[:id]}")
        end

        monitor.track_request(:info, 'Claims show success', 'travel_pay.claims.show',
                              tags: ['result:success'])
        render json: claim, status: :ok
      rescue => e
        monitor.track_request(:warn, 'Claims show failure', 'travel_pay.claims.show',
                              error: e.message, tags: ['result:failure'])
        raise
      end

      def create
        submitted_claim = execute_smoc_transaction
        render json: submitted_claim, status: :created
      end

      private

      def auth_manager
        @auth_manager ||= TravelPay::AuthManager.new(Settings.travel_pay.client_number, @current_user)
      end

      def claims_service
        @claims_service ||= TravelPay::ClaimsService.new(auth_manager, @current_user)
      end

      def appts_service
        @appts_service ||= TravelPay::AppointmentsService.new(auth_manager)
      end

      def expense_service
        @expense_service ||= TravelPay::ExpensesService.new(auth_manager)
      end

      def increment_smoc_statsd(result)
        level = result == 'success' ? :info : :warn
        monitor.track_request(level, "SMOC create #{result}", 'travel_pay.claims.smoc.create',
                              tags: ["result:#{result}"])
      end

      def fetch_claim_details(claim_id)
        claims_service.get_claim_details(claim_id)
      end

      def execute_smoc_transaction
        monitor.log(:info, 'SMOC transaction START')
        appt_id = find_or_create_appt_id!('SMOC', params)
        claim_id = create_claim(appt_id, 'SMOC')
        monitor.log(:info, "SMOC transaction: Add expense to claim #{claim_id.slice(0, 8)}")
        expense_service.add_expense({ 'claim_id' => claim_id, 'appt_date' => params['appointment_date_time'] })
        monitor.log(:info, "SMOC transaction: Submit claim #{claim_id.slice(0, 8)}")
        submitted_claim = claims_service.submit_claim(claim_id)
        monitor.log(:info, 'SMOC transaction END')
        increment_smoc_statsd('success')
        submitted_claim
      rescue
        increment_smoc_statsd('failure')
        raise
      end

      def check_smoc_feature_flag
        unless Flipper.enabled?(:travel_pay_submit_mileage_expense, @current_user)
          message = 'Travel Pay mileage expense submission unavailable per feature toggle'
          monitor.track_request(:error, message, 'travel_pay.claims.smoc.feature_flag_denied')
          raise Common::Exceptions::ServiceUnavailable, message:
        end
      end

      def scrub_logs
        logger.filter = lambda do |log|
          if log.name =~ /TravelPay/
            # Safely scrub :params
            log.payload[:params]['id'] = 'SCRUBBED_CLAIM_ID' if log.payload[:params].is_a?(Hash)

            # Safely scrub :path
            if log.payload[:path].is_a?(String)
              log.payload[:path] = log.payload[:path].gsub(%r{(.+claims/)(.+)}, '\1SCRUBBED_CLAIM_ID')
            end

            # Safely scrub :referer if present
            if log.named_tags&.key?(:referer) && log.named_tags[:referer].is_a?(String)
              log.named_tags[:referer] = log.named_tags[:referer].gsub(%r{(.+claims/)(.+)(.+)}, '\1SCRUBBED_CLAIM_ID')
            end
          end

          true
        end
      end
    end
  end
end
