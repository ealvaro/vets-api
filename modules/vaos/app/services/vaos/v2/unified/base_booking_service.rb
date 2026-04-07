# frozen_string_literal: true

module VAOS
  module V2
    module Unified
      ##
      # Abstract strategy for unified appointment booking. VA bookings use a single
      # {VAOS::V2::AppointmentsService#post_appointment} call; EPS uses draft-then-submit.
      # Concrete VA and EPS booking services implement {#perform_booking}; callers use
      # {#book}, which validates the result, logs metrics, and handles errors automatically.
      #
      class BaseBookingService
        STATSD_KEY_PREFIX = 'api.vaos.unified_booking'

        FAILURE_LOG_MESSAGE = "#{STATSD_KEY_PREFIX}: unified booking request failed".freeze
        ARGUMENT_ERROR_CONTEXT_KEYS = %i[missing_keys blank_keys].freeze

        # Every successful {#book} return value must be a Hash that includes these keys.
        # Optional keys: +:start+ (Time, DateTime, or ISO 8601 string).
        REQUIRED_CONFIRMATION_KEYS = %i[appointment_id provider_type status].freeze
        OPTIONAL_CONFIRMATION_KEYS = %i[start].freeze

        ##
        # Template method — calls {#perform_booking}, validates the result, logs metrics,
        # and returns the normalized confirmation. Subclasses override {#perform_booking}.
        #
        # @param user [User] authenticated veteran
        # @param provider [VAOS::V2::Unified::BaseProvider] unified provider (VA or community care)
        # @param slot [VAOS::V2::Unified::BaseSlot] selected slot
        # @param params [Hash] source-specific booking parameters
        # @return [Hash] normalized booking confirmation (see {.confirmation_shape})
        #
        def book(user:, provider:, slot:, params:)
          confirmation = perform_booking(user:, provider:, slot:, params:)
          confirmation = validate_booking_confirmation!(confirmation)
          log_booking_success(provider_type: confirmation[:provider_type])
          confirmation
        rescue => e
          log_booking_failure(e, provider_type: provider&.provider_type)
          raise
        end

        ##
        # Documents the contract for {#book} success responses.
        #
        # @return [Hash] description of required and optional keys
        #
        def self.confirmation_shape
          {
            required: REQUIRED_CONFIRMATION_KEYS,
            optional: OPTIONAL_CONFIRMATION_KEYS,
            description: 'Normalized appointment confirmation for the unified booking endpoint.'
          }
        end

        private

        ##
        # Subclasses implement this to perform the actual booking and return a raw
        # confirmation Hash. The base class {#book} validates and logs automatically.
        # Subclasses should keep this private.
        #
        def perform_booking(user:, provider:, slot:, params:)
          raise NotImplementedError, "#{self.class.name} must implement #perform_booking"
        end

        ##
        # Builds the normalized confirmation hash. Implementations should pass
        # +provider_type+ from +provider.provider_type+ when possible.
        #
        def build_booking_confirmation(appointment_id:, provider_type:, status:, start: nil)
          confirmation = {
            appointment_id: appointment_id.to_s,
            provider_type: provider_type.to_s,
            status: status.to_s
          }
          confirmation[:start] = start unless start.nil?
          confirmation
        end

        ##
        # Raises if +hash+ is missing {REQUIRED_CONFIRMATION_KEYS} or any required value is blank;
        # returns +hash+ (symbolized) otherwise.
        #
        def validate_booking_confirmation!(hash)
          unless hash.is_a?(Hash)
            log_booking_argument_error(reason: 'invalid_confirmation_type')
            raise ArgumentError, "Booking confirmation must be a Hash, got #{hash.class.name}"
          end

          hash = hash.symbolize_keys if hash.respond_to?(:symbolize_keys)
          missing = REQUIRED_CONFIRMATION_KEYS - hash.keys
          if missing.any?
            log_booking_argument_error(reason: 'invalid_confirmation', missing_keys: missing.map(&:to_s))
            raise ArgumentError, "Booking confirmation missing keys: #{missing.join(', ')}"
          end

          blank_required = REQUIRED_CONFIRMATION_KEYS.select { |key| hash[key].blank? }
          if blank_required.any?
            log_booking_argument_error(reason: 'invalid_confirmation', blank_keys: blank_required.map(&:to_s))
            raise ArgumentError, "Booking confirmation has blank required values: #{blank_required.join(', ')}"
          end

          hash
        end

        def log_booking_success(provider_type:)
          Rails.logger.info("#{STATSD_KEY_PREFIX}.success", { provider_type: provider_type.to_s })
          StatsD.increment("#{STATSD_KEY_PREFIX}.success", tags: ["provider_type:#{provider_type}"])
        end

        def log_booking_failure(error, provider_type:)
          Rails.logger.error(
            FAILURE_LOG_MESSAGE,
            {
              error_class: error.class.name,
              provider_type: provider_type.to_s
            }
          )
          StatsD.increment(
            "#{STATSD_KEY_PREFIX}.failure",
            tags: [
              "provider_type:#{provider_type}",
              "error_type:#{error.class.name.demodulize.underscore}"
            ]
          )
        end

        def log_booking_argument_error(reason:, **safe_context)
          payload = { reason: reason.to_s }
          payload.merge!(safe_context.slice(*ARGUMENT_ERROR_CONTEXT_KEYS)) if safe_context.present?
          Rails.logger.error("#{STATSD_KEY_PREFIX}.argument_error", payload)
          StatsD.increment("#{STATSD_KEY_PREFIX}.argument_error", tags: ["reason:#{reason}"])
        end
      end
    end
  end
end
