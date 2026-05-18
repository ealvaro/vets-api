# frozen_string_literal: true

require 'unique_user_events/event_registry'

module UniqueUserEvents
  # Oracle Health specific functionality for unique user metrics
  #
  # This module handles the generation of Oracle Health site-specific events
  # based on user facility registrations and tracked events.
  module OracleHealth
    # Parses and validates a comma-separated facility ID setting from AWS Parameter Store.
    # Uses ActiveModel::Type::Boolean cast to safely handle nil, false, and 0 values
    # before string conversion (prevents nil -> "nil", false -> "false").
    # Validates that all IDs are 3-digit numbers (VA facility ID format).
    # Returns empty frozen array if the value is falsy or validation fails.
    #
    # @param raw_value [String, Integer, nil, Boolean] the raw Settings value
    # @return [Array<String>] parsed and validated facility IDs (frozen)
    def self.parse_facility_ids(raw_value)
      ids = if ActiveModel::Type::Boolean.new.cast(raw_value)
              raw_value.to_s.split(',').map(&:strip).compact_blank
            else
              []
            end

      # Validate facility IDs are 3-digit numbers
      invalid_ids = ids.reject { |id| id.to_s =~ /^\d{3}$/ }
      if invalid_ids.any?
        Rails.logger.error(
          'UniqueUserEvents::OracleHealth: Invalid facility IDs in ' \
          "Settings.unique_user_metrics.oracle_health_tracked_facility_ids: #{invalid_ids.join(', ')}. " \
          'VA facility IDs must be 3-digit numbers. Using empty array.'
        )
        [].freeze
      else
        ids.map(&:to_s).freeze
      end
    end

    # Tracked facility IDs that should generate OH events
    # Loaded from Settings.unique_user_metrics.oracle_health_tracked_facility_ids
    TRACKED_FACILITY_IDS = parse_facility_ids(
      Settings.unique_user_metrics&.oracle_health_tracked_facility_ids
    )

    # Event suffix for Oracle Health facility-specific events (explicit facility context)
    OH_EVENT_SUFFIX = '_oh_'

    # Events that should generate Oracle Health site-specific events
    # Uses EventRegistry constants to avoid string duplication
    TRACKED_EVENTS = [
      EventRegistry::MEDICAL_RECORDS_ALLERGIES_ACCESSED,
      EventRegistry::MEDICAL_RECORDS_VACCINES_ACCESSED,
      EventRegistry::MEDICAL_RECORDS_LABS_ACCESSED,
      EventRegistry::MEDICAL_RECORDS_NOTES_ACCESSED,
      EventRegistry::MEDICAL_RECORDS_VITALS_ACCESSED,
      EventRegistry::MEDICAL_RECORDS_CONDITIONS_ACCESSED
    ].freeze

    # Generate facility-specific events for a user and event
    #
    # This method has two modes of operation:
    #
    # 1. With event_facility_ids (explicit facility context):
    #    - Generates `#{event_name}_oh_#{facility_id}` for matching facilities
    #    - Does NOT check TRACKED_EVENTS - any event can generate site-specific variants
    #    - Use this when the operation context provides facility info (e.g., prescription refill)
    #    - Validates facilities are both tracked AND actual OH facilities for the user
    #
    # 2. Without event_facility_ids (user-based):
    #    - Generates `#{event_name}_oh_site_#{facility_id}` for matching facilities
    #    - Only generates events for event names in TRACKED_EVENTS
    #    - Uses the user's Cerner facilities filtered by tracked facilities
    #
    # @param user [User] the authenticated User object
    # @param event_name [String] Name of the original event
    # @param event_facility_ids [Array<String>, nil] Optional facility IDs from operation context.
    #   When provided, these are checked against tracked facilities and user's cerner_facility_ids,
    #   and TRACKED_EVENTS validation is bypassed (caller is responsible for appropriate usage).
    # @return [Array<String>] Array of facility-specific event names to be logged
    def self.generate_events(user:, event_name:, event_facility_ids: nil)
      if event_facility_ids
        matching_facilities = filter_tracked_oh_facilities(event_facility_ids, user)
        matching_facilities.map { |facility_id| "#{event_name}#{OH_EVENT_SUFFIX}#{facility_id}" }
      else
        return [] unless TRACKED_EVENTS.include?(event_name)

        matching_facilities = get_user_tracked_facilities(user)
        matching_facilities.map { |facility_id| "#{event_name}_oh_site_#{facility_id}" }
      end
    end

    # Filter provided facility IDs to only include tracked OH facilities
    # that are also confirmed as Cerner/OH facilities for this user
    #
    # @param facility_ids [Array<String>] Array of facility IDs to filter
    # @param user [User] the authenticated User object
    # @return [Array<String>] Array of matching facility IDs
    def self.filter_tracked_oh_facilities(facility_ids, user)
      return [] if facility_ids.blank?

      normalized_ids = facility_ids.map(&:to_s)
      tracked_user_facilities = get_user_tracked_facilities(user)
      normalized_ids & tracked_user_facilities
    end

    # Get user's OH facilities that match tracked facilities
    #
    # @param user [User] the authenticated User object
    # @return [Array<String>] Array of matching facility IDs
    def self.get_user_tracked_facilities(user)
      cerner_ids = (user.cerner_facility_ids || []).map(&:to_s)
      cerner_ids & TRACKED_FACILITY_IDS
    end

    private_class_method :get_user_tracked_facilities, :filter_tracked_oh_facilities, :parse_facility_ids
  end
end
