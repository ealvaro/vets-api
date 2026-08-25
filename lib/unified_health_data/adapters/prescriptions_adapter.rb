# frozen_string_literal: true

require 'mhv/oh_facilities_helper/service'
require_relative 'vista_prescription_adapter'
require_relative 'oracle_health_prescription_adapter'
require_relative '../constants'
require_relative '../operation_outcome_detector'

module UnifiedHealthData
  module Adapters
    class PrescriptionsAdapter
      # Prescription status constants (STATUS_* / DISP_*) live in Constants::PrescriptionStatuses.
      include UnifiedHealthData::Constants::PrescriptionStatuses

      # Number of days after the most recent shipped date during which a prescription remains trackable.
      SHIPPED_TRACKING_WINDOW_DAYS = 15

      # Number of days a just-requested refill stays surfaced as in-flight ("Active: Submitted" /
      # "Active: Refill in Process") while VistA lags flipping the upstream disp_status.
      REFILL_IN_FLIGHT_WINDOW_DAYS = 3

      # Default number of days a VistA refill stays surfaced as "Active: Refill in Process"
      # after the request while it is transmitted to CMOP and awaiting a dispense. VistA
      # momentarily reports plain "Active" during this handoff. Overridable via
      # Settings.mhv.uhd.cmop_in_process_window_days so the ceiling can be tuned without a deploy.
      CMOP_IN_PROCESS_WINDOW_DEFAULT_DAYS = 15

      # Emitted for every VistA prescription suppressed at a station that is live on Oracle
      # Health. Only emitted when the feature flag is on, so it doubles as a rollout signal.
      STATSD_VISTA_RX_AT_OH_STATION = 'api.uhd.vista_rx_at_oh_station.detected'
      # Gauge of how many stations are configured for suppression. A curated list going stale is
      # otherwise indistinguishable from "no stations have cut over yet", so alert if this is 0
      # while the flag is on, or if it has not moved across a known cutover date. Gated with the
      # rest of the guard: with the flag off the list size has no consequences, and reporting it
      # anyway would suggest suppression is happening when none is.
      STATSD_OH_STATION_COUNT = 'api.uhd.vista_rx_at_oh_station.configured_stations'

      def initialize(current_user = nil)
        @current_user = current_user
        @vista_adapter = VistaPrescriptionAdapter.new
        @oracle_adapter = OracleHealthPrescriptionAdapter.new(current_user)
      end

      # @param body [Hash] The raw UHD response body
      # @param current_only [Boolean] When true, excludes discontinued/expired meds older than 180 days
      # @return [Hash] Hash with :prescriptions (Array) and :metadata (Hash) keys
      def parse(body, current_only: false)
        raise ArgumentError, 'UHD returned an empty response body' if body.nil?

        prescriptions = []

        # Parse VistA medications
        vista_medications = parse_vista_medications(body)
        prescriptions.concat(vista_medications) if vista_medications.present?

        # Parse Oracle Health medications
        oracle_medications = parse_oracle_medications(body)
        prescriptions.concat(oracle_medications) if oracle_medications.present?

        log_upstream_parse_counts(
          vista_count: vista_medications.size,
          oracle_count: oracle_medications.size,
          body:
        )

        # Exclude certain prescriptions based on business rules
        prescriptions.reject! { |prescription| should_exclude_prescription?(prescription) }

        apply_oh_station_vista_suppression(prescriptions)

        # Apply current filtering if requested
        prescriptions = apply_current_filtering(prescriptions) if current_only

        apply_flagged_status_adjustments(prescriptions)

        { prescriptions:, metadata: { has_failed_stations: any_source_failed?(body) } }
      end

      private

      # Read-time, flag-gated status adjustments applied after parsing and filtering. Ordering
      # matters: shipped-tracking runs first so dispense-based states take precedence, then the
      # interim submission bridge, then the CMOP in-process bridge (each only touches meds still
      # showing plain 'Active', so they do not clobber each other).
      def apply_flagged_status_adjustments(prescriptions)
        # Shipped tracking (sets is_trackable to false if shipped beyond the 15-day window).
        if Flipper.enabled?(:mhv_medications_management_improvements, @current_user)
          apply_shipped_tracking_logic(prescriptions)
        end

        # Interim refill-status bridging while upstream (VistA) status flips lag behind requests.
        if Flipper.enabled?(:mhv_mmi_refill_status_bandaid_temp, @current_user)
          apply_submission_date_bridge(prescriptions)
        end

        # Restore "Active: Refill in Process" for VistA refills mid-CMOP-handoff, when VistA
        # momentarily reports plain "Active". Independent of the interim bandaid above so it
        # persists after that flag is removed; upstream does not correct the CMOP flip-back.
        return unless Flipper.enabled?(:mhv_medications_cmop_refill_in_process_bridge, @current_user)

        apply_cmop_in_process_bridge(prescriptions)
      end

      def apply_current_filtering(prescriptions)
        filtered = prescriptions.reject { |prescription| prescription_not_current?(prescription) }

        Rails.logger.info(
          message: 'Applied current filtering to prescriptions',
          original_count: prescriptions.size,
          filtered_count: filtered.size,
          excluded_count: prescriptions.size - filtered.size
        )

        filtered
      end

      def prescription_not_current?(prescription)
        # Exclude discontinued/expired medications that are older than 180 days
        if %w[discontinued expired].include?(prescription.refill_status) &&
           prescription.expiration_date.present?
          begin
            expiration_date = Date.parse(prescription.expiration_date)
            return true if expiration_date < 180.days.ago
          rescue Date::Error, TypeError
            # If date parsing fails, don't exclude based on date
            # Only log last 4 digits of prescription ID for privacy
            rx_suffix = prescription.id.to_s.last(4)
            Rails.logger.warn("Invalid expiration date for rx ending in #{rx_suffix}: #{prescription.expiration_date}")
          end
        end

        false
      end

      # A station that has gone live on Oracle Health keeps returning its historical VistA records
      # through UHD, and those records can still carry is_refillable/is_renewable from before the
      # cutover. Acting on them would submit a refill against an EHR that no longer owns the
      # prescription, so both affordances are withdrawn. The record itself is left alone: it stays
      # in the list, keeps its display status, and is not deduplicated against its OH counterpart.
      #
      # Entirely flag-gated: with the flag off this emits no metrics and touches nothing. Fails
      # open twice over, since an empty station list also means the guard cannot fire -- wrongly
      # blocking a Veteran's refill is worse than the stale record this guards against.
      def apply_oh_station_vista_suppression(prescriptions)
        return unless Flipper.enabled?(:mhv_medications_suppress_vista_rx_at_oh_stations, @current_user)

        StatsD.gauge(STATSD_OH_STATION_COUNT, oh_suppression_stations.size)
        return if oh_suppression_stations.empty?

        prescriptions.each do |rx|
          next unless vista_source?(rx) && rx.station_number.present?

          station = normalized_station(rx.station_number)
          next unless oh_suppression_stations.include?(station)

          StatsD.increment(STATSD_VISTA_RX_AT_OH_STATION, tags: ["station_number:#{station}"])

          rx.is_refillable = false
          rx.is_renewable = false
        end
      end

      # Hand-curated station numbers, updated at each cutover via Parameter Store. Matched exactly:
      # no parent-station fallback, so listing '610' never suppresses '610A4'. Cutovers move 2-4
      # stations every couple of months, so an explicit list is cheaper to operate and safer than
      # deriving system-level state from a source that flags whole systems at once.
      def oh_suppression_stations
        @oh_suppression_stations ||= MHV::OhFacilitiesHelper::Service.parse_facility_setting(
          Settings.mhv.oh_facility_checks.vista_suppression_oh_stations
        ).map { |station| normalized_station(station) }
      end

      # Child stations carry alphanumeric suffixes ('610A4', '528GQ01'), so casing has to be
      # normalized on both sides or an exact match silently misses. Stray quotes are dropped too:
      # the setting is hand-typed into Parameter Store, and someone quoting the list would
      # otherwise leave a quote welded to the first and last station.
      def normalized_station(station_number)
        station_number.to_s.delete('"\'').strip.upcase
      end

      def should_exclude_prescription?(prescription)
        # Mirror logic from Mobile::V0::PrescriptionsController#resource_data_modifications

        # Exclude Partial Fill (PF) and Pending Prescriptions (PD)
        display_pending_meds = Flipper.enabled?(:mhv_medications_display_pending_meds, @current_user)
        if display_pending_meds
          return true if prescription.prescription_source == 'PF'
        elsif %w[PF PD].include?(prescription.prescription_source)
          # TODO: remove this line when PF and PD are allowed on the app
          return true
        end

        # Exclude inpatient prescriptions
        # See https://build.fhir.org/valueset-medicationrequest-admin-location.html
        return true if prescription.category&.include?('inpatient')

        false
      end

      def parse_vista_medications(body)
        vista_data = body[SourceConstants::VISTA]
        return [] unless vista_data && vista_data['medicationList']

        medications = vista_data.dig('medicationList', 'medication')
        return [] unless medications.is_a?(Array)

        medications.map { |med| @vista_adapter.parse(med) }.compact
      end

      def parse_oracle_medications(body)
        oracle_data = body[SourceConstants::ORACLE_HEALTH]
        return [] unless oracle_data && oracle_data['entry']

        entries = oracle_data['entry']
        return [] unless entries.is_a?(Array)

        # Filter for MedicationRequest resources
        medication_requests = entries.select do |entry|
          entry.dig('resource', 'resourceType') == 'MedicationRequest'
        end

        medication_requests.map { |entry| @oracle_adapter.parse(entry['resource']) }.compact
      end

      # For prescriptions with disp_status 'Active: Shipped', checks the tracking shipped date
      # against a 15-day window. If shipped beyond 15 days, sets is_trackable to false.
      def apply_shipped_tracking_logic(prescriptions)
        prescriptions.each do |rx|
          next unless rx.disp_status == DISP_ACTIVE_SHIPPED

          most_recent_date = most_recent_shipped_date(rx)
          next unless most_recent_date

          rx.is_trackable = false unless most_recent_date >= SHIPPED_TRACKING_WINDOW_DAYS.days.ago
        end
      end

      def most_recent_shipped_date(rx)
        dates = rx.tracking.filter_map do |t|
          Time.zone.parse(t[:complete_date_time])
        rescue ArgumentError, TypeError
          nil
        end
        dates.max
      end

      # Whether the prescription originates from VistA. Used to gate the submission-date bridge,
      # which only applies to VistA prescriptions.
      #
      # @param rx [UnifiedHealthData::Prescription] the prescription to evaluate
      # @return [Boolean] true when the prescription originates from VistA
      def vista_source?(rx)
        rx.source_ehr == UnifiedHealthData::Prescription::SOURCE_EHR_VISTA
      end

      def most_recent_dispensed_date(rx)
        raw = rx.sorted_dispensed_date.presence || rx.dispensed_date.presence
        return nil if raw.blank?

        Time.zone.parse(raw.to_s)
      rescue ArgumentError, TypeError
        nil
      end

      # Keeps a prescription showing "Active: Submitted" after a refill request while upstream
      # catches up, using persisted dates instead of the transient Redis badge. A submission newer
      # than the last fill (or a submission with no fill yet) means the refill is still pending.
      # Runs after the dispense-based tracking steps so those (shipped/awaiting) take precedence:
      # only prescriptions still showing plain 'Active' are bridged here. Gated to VistA only:
      # Oracle Health also populates refill_submit_date (from order Task executionPeriod), so an
      # ungated bridge would fire on OH prescriptions that OH already surfaces correctly.
      def apply_submission_date_bridge(prescriptions)
        prescriptions.each do |rx|
          next unless vista_source?(rx)
          next unless rx.disp_status == DISP_ACTIVE
          next unless refill_still_pending?(rx)

          rx.disp_status = DISP_ACTIVE_SUBMITTED
          rx.refill_status = STATUS_SUBMITTED
          rx.is_refillable = false
          # No shipment exists yet for a still-pending refill, so clear the upstream-sourced
          # is_trackable flag to avoid offering a tracking affordance against an empty list.
          rx.is_trackable = false
        end
      end

      def refill_still_pending?(rx)
        submit = parse_bridge_time(rx.refill_submit_date)
        return false if submit.nil?

        # Bound the bridge to the refill in-flight window. Without an upper bound a request
        # that never receives a dispense upstream would hold the prescription at "Active: Submitted"
        # with is_refillable=false indefinitely, re-creating the stuck-Submitted trap. After the
        # window elapses we stop bridging so the prescription falls back to its upstream status.
        return false if submit < REFILL_IN_FLIGHT_WINDOW_DAYS.days.ago

        # A fill that shipped on/after the submit date means this refill has been filled, so it is
        # no longer pending regardless of the projected refill_date. Compare the shipment completion
        # date against the submit date (rather than a date-agnostic presence check) so tracking left
        # over from a *previous* fill cycle does not suppress a genuinely new request.
        return false if shipped_since?(rx, submit)

        # An actual dispense on/after the submit date means the request has already been filled.
        # refill_date below is VistA's *projected* next-available date, which is cleared/moved once a
        # fill lands; relying on it alone would re-stamp an already-dispensed refill back to
        # "Active: Submitted". Guard on the real dispensed date before consulting refill_date. A
        # same-day dispense counts as filled (dispensed >= submit) so a completed fill is never
        # re-bridged.
        dispensed = most_recent_dispensed_date(rx)
        return false if dispensed && dispensed.to_date >= submit.to_date

        fill = parse_bridge_time(rx.refill_date)
        return true if fill.nil? # submitted, not yet filled

        submit > fill
      end

      # Restores "Active: Refill in Process" for a VistA prescription whose requested refill has
      # been transmitted to CMOP but not yet dispensed. During that handoff VistA reports the
      # aggregate disp_status as plain "Active" (with is_refillable true), so a mid-fill med looks
      # idle. Only prescriptions still showing plain 'Active' are bridged, so upstream states such
      # as "Active: Shipped" or an already-restored "Active: Refill in Process" take precedence.
      # Gated to VistA only: Oracle Health surfaces its own in-process status correctly.
      #
      # Unlike apply_submission_date_bridge, this deliberately leaves is_refillable and
      # is_trackable untouched: the veteran may still request an additional refill before the
      # dispense lands, and VistA remains the authority that accepts or rejects that request.
      def apply_cmop_in_process_bridge(prescriptions)
        prescriptions.each do |rx|
          next unless vista_source?(rx)
          next unless rx.disp_status == DISP_ACTIVE
          next unless cmop_refill_in_process?(rx)

          rx.disp_status = DISP_ACTIVE_REFILL_IN_PROCESS
          rx.refill_status = STATUS_REFILL_IN_PROCESS
        end
      end

      def cmop_refill_in_process?(rx)
        submit = most_recent_rf_submit_date(rx)
        return false if submit.nil?

        # Bound off the refill-record date so a request that never receives a dispense upstream
        # does not hold the prescription at "Active: Refill in Process" forever. After the
        # (configurable) CMOP window elapses we stop bridging and fall back to upstream status.
        return false if submit < cmop_in_process_window_days.days.ago

        # Release the instant a real fill lands: a shipment or dispense on/after the request date
        # means CMOP has produced the fill, so upstream's plain "Active" is now correct. Compare
        # against the submit date so tracking/dispenses left from a prior cycle do not release it.
        return false if shipped_since?(rx, submit)

        dispensed = most_recent_dispensed_date(rx)
        return false if dispensed && dispensed.to_date >= submit.to_date

        true
      end

      # Most recent refill-request date across the prescription's refill records (rx.dispenses),
      # each of which carries the submit date for its own fill cycle. Anchoring on the refill
      # record rather than the top-level refill_submit_date keeps the bridge stable across the
      # CMOP flip-back, where VistA may clear/move the aggregate submission date.
      def most_recent_rf_submit_date(rx)
        dates = rx.dispenses.filter_map do |d|
          next unless d.is_a?(Hash)

          parse_bridge_time(d[:refill_submit_date])
        end
        dates.max
      end

      # Configurable ceiling for the CMOP in-process window. Settings values may arrive as
      # strings, integers, or nil (Parameter Store + env_parse_values), so coerce and fall back.
      def cmop_in_process_window_days
        configured = Settings.mhv&.uhd&.cmop_in_process_window_days.to_i
        configured.positive? ? configured : CMOP_IN_PROCESS_WINDOW_DEFAULT_DAYS
      end

      def parse_bridge_time(value)
        return nil if value.blank?

        Time.zone.parse(value.to_s)
      rescue ArgumentError, TypeError
        nil
      end

      # Whether any tracking entry reports a shipment completed on/after the submit date. Compares
      # each completion date to the submit date so a shipment from a prior fill cycle does not count
      # as evidence that the just-submitted refill has already shipped.
      def shipped_since?(rx, submit)
        return false if rx.tracking.blank?

        rx.tracking.any? do |t|
          next false unless t.is_a?(Hash)

          completed = parse_bridge_time(t[:complete_date_time])
          completed && completed.to_date >= submit.to_date
        end
      end

      # Checks whether either data source reported a failure in the UHD response.
      # VistA: failedStationList is a non-empty string (comma-separated station numbers).
      # Oracle Health: entry array contains an OperationOutcome resource with error-severity issues.
      def any_source_failed?(body)
        vista_failed?(body) || oracle_health_failed?(body)
      end

      def vista_failed?(body)
        body.dig(SourceConstants::VISTA, 'failedStationList').present?
      end

      # Defense-in-depth: today the Client raises UpstreamPartialFailure for
      # error/fatal OperationOutcomes before the adapter runs, so this branch
      # is not reachable. We keep it aligned with OperationOutcomeDetector's
      # ERROR_SEVERITIES so the flag stays correct if that upstream flow changes.
      def oracle_health_failed?(body)
        oracle_data = body[SourceConstants::ORACLE_HEALTH]
        return false if oracle_data.blank?

        entries = oracle_data['entry']
        return false unless entries.is_a?(Array) && entries.present?

        entries.any? do |e|
          next false unless e.dig('resource', 'resourceType') == 'OperationOutcome'

          issues = e.dig('resource', 'issue')
          issues.is_a?(Array) && issues.any? do |i|
            OperationOutcomeDetector::ERROR_SEVERITIES.include?(i['severity'])
          end
        end
      end

      # Logs the raw counts from each data source after initial parsing.
      # This is the earliest point where we know what the upstream returned
      def log_upstream_parse_counts(vista_count:, oracle_count:, body:)
        vista_data = body[SourceConstants::VISTA]
        oracle_data = body[SourceConstants::ORACLE_HEALTH]

        Rails.logger.info(
          message: 'UHD prescriptions upstream parse counts',
          vista_raw_medications_parsed: vista_count,
          oracle_raw_medications_parsed: oracle_count,
          vista_medication_list_is_array: vista_data&.dig('medicationList', 'medication').is_a?(Array),
          oracle_entry_is_array: oracle_data&.dig('entry').is_a?(Array),
          vista_failed_station_list: vista_data&.dig('failedStationList').presence,
          service: 'unified_health_data'
        )
      end
    end
  end
end
