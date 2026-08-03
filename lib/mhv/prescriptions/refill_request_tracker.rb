# frozen_string_literal: true

require 'digest'

module MHV
  module Prescriptions
    # Tracks recently submitted refill orders to prevent immediate duplicate submissions
    # while upstream prescription status catches up.
    class RefillRequestTracker
      CACHE_KEY_PREFIX = 'mhv:prescriptions:refill_claim'
      DEFAULT_CLAIM_TTL = 15.minutes
      DUPLICATE_REFILL_ERROR = 'Refill request already in progress'
      SERVICE_UNAVAILABLE_ERROR = 'Service unavailable'

      # Reads the claim (dup-guard) lifetime from Settings with safe coercion.
      # The config gem may deliver nil/String/Integer, so we coerce explicitly and
      # fall back to DEFAULT_CLAIM_TTL for missing/blank/zero/non-numeric values.
      def self.configured_ttl
        seconds = Settings.dig(:mhv, :rx, :refill_claim_ttl_seconds).to_i
        seconds.positive? ? seconds.seconds : DEFAULT_CLAIM_TTL
      end

      def initialize(user, cache: Rails.cache, ttl: RefillRequestTracker.configured_ttl)
        @user = user
        @cache = cache
        @ttl = ttl
      end

      # Claims refill orders. Orders that are already claimed are returned as failed.
      # @return [Array<Array<Hash>, Array<Hash>>] [claimed_orders, duplicate_failures]
      def claim_orders(orders)
        Array(orders).each_with_object([[], []]) do |order, (claimed_orders, duplicate_failures)|
          if claim_order(order)
            claimed_orders << order
          else
            duplicate_failures << duplicate_failure(order)
          end
        end
      end

      def release_orders(orders)
        Array(orders).each do |order|
          key = cache_key_for_order(order)
          @cache.delete(key) if key
        end
      rescue => e
        Rails.logger.warn(
          "RefillRequestTracker cache delete failed: #{e.class} #{e.message}"
        )
      end

      # Mutates matching prescriptions in place to reflect a recently submitted refill.
      def apply_submitted_state!(prescriptions, in_progress_status:)
        key_map = claim_keys_by_prescription(prescriptions)
        return prescriptions if key_map.empty?

        claimed_keys = claimed_cache_keys(key_map.keys)
        return prescriptions if claimed_keys.empty?

        key_map.each do |cache_key, prescription|
          next unless claimed_keys.include?(cache_key)

          apply_in_progress_state(prescription, in_progress_status)
        end

        prescriptions
      end

      private

      def claim_order(order)
        key = cache_key_for_order(order)
        return false if key.blank?

        @cache.write(key, Time.current.to_i, expires_in: @ttl, unless_exist: true)
      rescue => e
        Rails.logger.warn(
          "RefillRequestTracker cache write failed (failing open): #{e.class} #{e.message}"
        )
        true
      end

      def duplicate_failure(order)
        {
          id: extract_order_id(order),
          error: DUPLICATE_REFILL_ERROR,
          station_number: extract_station_number(order)
        }
      end

      def apply_in_progress_state(prescription, in_progress_status)
        should_decrement = should_decrement_refill_remaining?(prescription)

        prescription.disp_status = in_progress_status if prescription.respond_to?(:disp_status=)
        prescription.refill_status = 'submitted' if prescription.respond_to?(:refill_status=)
        prescription.is_refillable = false if prescription.respond_to?(:is_refillable=)
        prescription.refill_submit_date = Time.current.iso8601 if prescription.respond_to?(:refill_submit_date=)

        return unless should_decrement
        return unless prescription.respond_to?(:refill_remaining) && prescription.respond_to?(:refill_remaining=)

        refill_remaining = prescription.refill_remaining
        return unless refill_remaining.is_a?(Integer) && refill_remaining.positive?

        prescription.refill_remaining = refill_remaining - 1
      end

      def should_decrement_refill_remaining?(prescription)
        already_submitted = prescription.respond_to?(:refill_status) &&
                            prescription.refill_status.to_s.casecmp('submitted').zero?
        has_submit_date = prescription.respond_to?(:refill_submit_date) && prescription.refill_submit_date.present?
        already_not_refillable = prescription.respond_to?(:is_refillable) && prescription.is_refillable == false

        !(already_submitted || has_submit_date || already_not_refillable)
      end

      def claim_keys_by_prescription(prescriptions)
        Array(prescriptions).each_with_object({}) do |prescription, key_map|
          cache_key = cache_key_for_prescription(prescription)
          key_map[cache_key] = prescription if cache_key
        end
      end

      def claimed_cache_keys(cache_keys)
        return [] if cache_keys.blank?

        cache_values = if @cache.respond_to?(:read_multi)
                         @cache.read_multi(*cache_keys)
                       else
                         cache_keys.index_with { |key| @cache.read(key) }
                       end

        cache_values.compact_blank.keys
      rescue => e
        Rails.logger.warn(
          "RefillRequestTracker cache read failed (failing open): #{e.class} #{e.message}"
        )
        []
      end

      def cache_key_for_order(order)
        cache_key(extract_station_number(order), extract_order_id(order))
      end

      def cache_key_for_prescription(prescription)
        return nil unless prescription.respond_to?(:station_number) && prescription.respond_to?(:prescription_id)

        cache_key(prescription.station_number, prescription.prescription_id)
      end

      def cache_key(station_number, prescription_id)
        station = station_number.to_s
        prescription = prescription_id.to_s
        user_key = user_key_component

        return nil if station.blank? || prescription.blank? || user_key.blank?

        hashed_user_key = Digest::SHA256.hexdigest(user_key)
        "#{CACHE_KEY_PREFIX}:#{hashed_user_key}:#{station}:#{prescription}"
      end

      def user_key_component
        @user_key_component ||= begin
          # Prefer ICN because refill operations are ICN-scoped at the upstream service.
          icn = @user.icn.presence
          uuid = @user.uuid.presence
          account_uuid = @user.user_account_uuid.presence
          icn || uuid || account_uuid
        end
      end

      def extract_station_number(order)
        return nil unless order.is_a?(Hash)

        order[:station_number] || order[:stationNumber] || order['station_number'] || order['stationNumber']
      end

      def extract_order_id(order)
        return nil unless order.is_a?(Hash)

        order[:id] || order['id']
      end
    end
  end
end
