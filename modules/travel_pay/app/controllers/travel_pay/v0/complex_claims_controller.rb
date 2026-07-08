# frozen_string_literal: true

require 'logging/monitor'

module TravelPay
  module V0
    class ComplexClaimsController < ApplicationController
      include FeatureFlagHelper
      include AppointmentHelper
      include ClaimHelper
      include IdValidation
      include ErrorHandling

      before_action :complex_claims_enabled?

      # Submits a previously created complex claim by claim_id.
      def submit
        claim_id = params[:claim_id]
        validate_uuid_exists!(claim_id, 'Claim')

        # TODO: add validation to verify there is a document associated to a given expense
        # TODO: possibly add validation to verify the claim id is valid
        Rails.logger.info(message: 'Submit complex claim')
        submitted_claim = claims_service.submit_claim(claim_id)

        increment_submit_statsd('success')
        render json: submitted_claim, status: :created
      rescue Common::Exceptions::BackendServiceException => e
        increment_submit_statsd('failure')
        raise if unified_error_handling_enabled?

        monitor.track_request(:error, "BTSSS error submitting complex claim: #{e.message}",
                              'travel_pay.claims.complex.submit.backend_error')
        render json: { error: 'Error submitting complex claim' }, status: e.original_status || :bad_gateway
      rescue Faraday::Error => e
        increment_submit_statsd('failure')
        raise if unified_error_handling_enabled?

        legacy_handle_submit_error(e)
      rescue
        increment_submit_statsd('failure')
        raise
      end

      # Creates a complex claim, resolving or creating an appointment first.
      def create
        appointment_source = validate_appointment_source!(request.query_parameters[:appointment_source])
        appt_id = resolve_appt_id!(validated_claim_params!)
        claim_id = create_claim(appt_id, 'Complex')
        increment_statsd(appointment_source, 'success')
        render json: { claimId: claim_id }, status: :created
      rescue Common::Exceptions::ResourceNotFound => e
        increment_statsd(appointment_source, 'failure')
        raise if unified_error_handling_enabled?

        legacy_handle_create_not_found(e)
      rescue Common::Exceptions::BackendServiceException => e
        increment_statsd(appointment_source, 'failure')
        raise if unified_error_handling_enabled?

        legacy_handle_create_backend_error(e)
      rescue Faraday::Error => e
        increment_statsd(appointment_source, 'failure')
        raise if unified_error_handling_enabled?

        legacy_handle_create_faraday_error(e)
      rescue
        increment_statsd(appointment_source, 'failure') if appointment_source
        raise
      end

      private

      def increment_statsd(appointment_source, result)
        StatsD.increment('travel_pay.claims.complex.create',
                         tags: ["appointment_source:#{appointment_source}", "result:#{result}"])
      end

      def resolve_appt_id!(permitted_params)
        appt_id = params[:appt_id]

        if appt_id.present?
          validate_uuid_exists!(appt_id, 'Appointment')
          Rails.logger.info('ComplexClaimsController#create: appt_id provided, skipping find_or_create_appt_id!')
          return appt_id
        end

        find_or_create_appt_id!('Complex', permitted_params)
      end

      VALID_CLAIM_TYPES = %w[community-care other].freeze

      def increment_submit_statsd(result)
        claim_type = resolve_claim_type(request.query_parameters[:claim_type])
        StatsD.increment('travel_pay.claims.complex.submit',
                         tags: ["result:#{result}", "claim_type:#{claim_type}"])
      end

      def resolve_claim_type(type)
        return 'unknown' if type.blank?
        return type if VALID_CLAIM_TYPES.include?(type)

        'unknown'
      end

      def base_required_fields
        %i[
          appointment_date_time
          facility_station_number
          appointment_type
          is_complete
        ]
      end

      def v4_additional_fields
        %i[appointment_name facility_name]
      end

      def allowed_claim_keys
        appointments_v4_enabled? ? base_required_fields + v4_additional_fields : base_required_fields
      end

      # Handles Faraday errors for both client (4xx) and server (5xx)
      # e: the Faraday error
      # default_message: fallback message if response body is missing
      # log_prefix: optional prefix for log message
      def handle_faraday_error(e, default_message, log_prefix: '')
        error_type = e.is_a?(Faraday::ClientError) ? 'client' : 'server'
        Rails.logger.error("#{log_prefix}Faraday #{error_type} error: #{e.message}")

        http_status = e.response&.dig(:status) ||
                      (e.is_a?(Faraday::ClientError) ? :bad_request : :internal_server_error)
        message = if e.response&.dig(:body).present?
                    e.response[:body]
                  else
                    default_message
                  end

        render json: { errors: [{ detail: message }] }, status: http_status
      end

      def legacy_handle_submit_error(e)
        case e
        when Faraday::ClientError
          handle_faraday_error(e, 'Invalid request for complex claim', log_prefix: 'Submitting complex claim: ')
        when Faraday::ServerError
          handle_faraday_error(e, 'Server error submitting complex claim', log_prefix: 'Submitting complex claim: ')
        else
          handle_faraday_error(e, 'Error creating complex claim', log_prefix: 'Submitting complex claim: ')
        end
      end

      def legacy_handle_create_faraday_error(e)
        Rails.logger.error("Faraday error creating complex claim: #{e.message}")
        status_code = (e.respond_to?(:response) && e.response && e.response[:status]) || :internal_server_error
        render json: { error: 'Error creating complex claim' }, status: status_code
      end

      def legacy_handle_create_not_found(e)
        monitor.track_request(:error, "Appointment not found: #{e.message}",
                              'travel_pay.claims.complex.create.not_found')
        render json: { error: e.message }, status: :not_found
      end

      def legacy_handle_create_backend_error(e)
        monitor.track_request(:error, "BTSSS error creating complex claim: #{e.message}",
                              'travel_pay.claims.complex.create.backend_error')
        render json: { error: 'Error creating complex claim' }, status: e.original_status || :bad_gateway
      end

      def monitor
        @monitor ||= Logging::Monitor.new('travel-pay-complex-claims')
      end

      def validated_claim_params!
        permitted = require_and_permit_claim_params(params)
        validate_required_params!(permitted)
        validate_datetime_format!(permitted[:appointment_date_time])
        permitted
      end

      def complex_claims_enabled?
        verify_feature_flag!(
          :travel_pay_enable_complex_claims,
          current_user,
          error_message: 'Travel Pay complex claim endpoint unavailable per feature toggle'
        )
      end

      def appointments_v4_enabled?
        Flipper.enabled?(:travel_pay_appt_add_v4_upgrade, current_user)
      end

      def require_and_permit_claim_params(params)
        params.require(:complex_claim).permit(*allowed_claim_keys)
      end

      def validate_required_params!(permitted_params)
        # Use allowed_claim_keys as the source of truth for required fields
        required_fields = allowed_claim_keys.map(&:to_s)

        # Find missing keys
        missing = required_fields.select do |key|
          value = permitted_params[key] || permitted_params[key.to_sym] # check string or symbol
          value.nil? || (value.respond_to?(:empty?) && value.empty?) # false is fine
        end

        return if missing.empty?

        raise Common::Exceptions::BadRequest.new(
          detail: "Missing required params: #{missing.join(', ')}"
        )
      end

      def render_bad_request(e)
        # Extract the first detail from errors array, fallback to generic
        error_detail = if e.respond_to?(:errors) && e.errors.any?
                         e.errors.first[:detail] || 'Bad request'
                       else
                         'Bad request'
                       end

        render json: { errors: [{ detail: error_detail }] }, status: :bad_request
      end

      def validate_datetime_format!(datetime_str)
        DateTime.iso8601(datetime_str)
      rescue ArgumentError
        raise Common::Exceptions::BadRequest.new(
          detail: 'Appointment date time must be a valid datetime'
        )
      end

      VALID_APPOINTMENT_SOURCES = %w[user-generated vaos].freeze

      def validate_appointment_source!(type)
        type = 'vaos' if type.blank?

        unless VALID_APPOINTMENT_SOURCES.include?(type)
          raise Common::Exceptions::BadRequest.new(
            detail: "Invalid appointment_source '#{type}'. Must be one of: #{VALID_APPOINTMENT_SOURCES.join(', ')}"
          )
        end

        type
      end
    end
  end
end
