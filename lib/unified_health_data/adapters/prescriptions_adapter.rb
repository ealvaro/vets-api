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

      # Default number of days a VistA refill stays surfaced as "Active: Refill in Process"
      # after the request while it is transmitted to CMOP and awaiting a dispense. VistA
      # momentarily reports plain "Active" during this handoff. Overridable via
      # Settings.mhv.uhd.cmop_in_process_window_days so the ceiling can be tuned without a deploy.
      CMOP_IN_PROCESS_WINDOW_DEFAULT_DAYS = 15

      # Incremented once per list fetch in which at least one affordance was actually withdrawn
      # at the tagged station, not once per affected prescription. Nothing caches the parse, so a
      # per-record counter would re-count the same prescriptions on every page load and read as
      # traffic rather than impact; counting fetches makes the series approximate "sessions
      # affected at this station", which is what sizing a rollout needs. Per-record volume lives
      # in the log line's suppressed_count.
      #
      # Only emitted when the feature flag is on, so it doubles as a rollout signal: after a
      # station is added to the list this is how you confirm suppression actually started there,
      # and a station going flat is how you catch a list that has gone stale.
      #
      # Deliberately tagged by station and nothing else. Datadog bills per unique tag
      # combination, and the diagnostic breakdowns worth having here (which affordance, what
      # display status) would multiply this counter's series for a question that is only asked
      # while stations are cutting over -- those live in the log line below instead.
      STATSD_SUPPRESSED_FETCHES = 'api.uhd.prescriptions.vista_suppression.affected_fetches'
      # Gauge of how many stations are configured for suppression. A curated list going stale is
      # otherwise indistinguishable from "no stations have cut over yet", so alert if this is 0
      # while the flag is on, or if it has not moved across a known cutover date. Gated with the
      # rest of the guard: with the flag off the list size has no consequences, and reporting it
      # anyway would suggest suppression is happening when none is.
      STATSD_CONFIGURED_STATIONS = 'api.uhd.prescriptions.vista_suppression.configured_stations'

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
      # CMOP in-process bridge (which only touches meds still showing plain 'Active').
      def apply_flagged_status_adjustments(prescriptions)
        # Shipped tracking (sets is_trackable to false if shipped beyond the 15-day window).
        if Flipper.enabled?(:mhv_medications_management_improvements, @current_user)
          apply_shipped_tracking_logic(prescriptions)
        end

        # Restore "Active: Refill in Process" for VistA refills mid-CMOP-handoff, when VistA
        # momentarily reports plain "Active". Gated together with MMI so it ships only to the
        # MMI rollout cohort.
        return unless Flipper.enabled?(:mhv_medications_cmop_refill_in_process_bridge, @current_user) &&
                      Flipper.enabled?(:mhv_medications_management_improvements, @current_user)

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

        StatsD.gauge(STATSD_CONFIGURED_STATIONS, oh_suppression_stations.size)
        return if oh_suppression_stations.empty?

        suppressed = prescriptions.filter_map do |rx|
          next unless vista_source?(rx) && rx.station_number.present?

          station = normalized_station(rx.station_number)
          next unless oh_suppression_stations.include?(station)
          # A record offering neither affordance -- an old discontinued med, say -- has nothing
          # to withdraw. Assigning false to it changes nothing, so skipping keeps both the counter
          # and the log a measure of what the guard actually did.
          next unless rx.is_refillable || rx.is_renewable

          # Captured before the assignment below, so the affordance still reads as what the
          # Veteran was being offered rather than what we left behind.
          entry = {
            station_number: station,
            affordance: suppressed_affordance(rx),
            disp_status: rx.disp_status.presence || 'none'
          }

          rx.is_refillable = false
          rx.is_renewable = false

          entry
        end

        count_affected_fetch(suppressed)
        log_suppression_breakdown(suppressed)
      end

      # One increment per station this fetch touched, however many of the Veteran's records were
      # affected there. A fetch can span stations, so uniq rather than a single increment.
      def count_affected_fetch(suppressed)
        suppressed.map { |entry| entry[:station_number] }.uniq.each do |station|
          StatsD.increment(STATSD_SUPPRESSED_FETCHES, tags: ["station_number:#{station}"])
        end
      end

      # Refill and renewal are offered independently by VistA and fail differently against an EHR
      # that no longer owns the prescription, so they are worth telling apart.
      def suppressed_affordance(rx)
        return 'both' if rx.is_refillable && rx.is_renewable

        rx.is_refillable ? 'refill' : 'renew'
      end

      # One line per list fetch, only when something was actually withdrawn, carrying the
      # breakdowns that answer "why did VistA still think these were actionable?" -- a display
      # status of 'Active' means VistA still considers the order live at a station it no longer
      # fills for, while a missing one points at the record. These are logged rather than tagged
      # onto the counter because log fields cost nothing per distinct value, where metric tags are
      # billed per combination and disp_status is passed through from upstream unbounded.
      #
      # PII/PHI-safe: counts and upstream status values only. No prescription id, drug name, sig
      # text, facility name or patient identifier, which is also why this cannot answer an
      # individual support ticket -- it is a population signal for sizing and root cause.
      def log_suppression_breakdown(suppressed)
        return if suppressed.empty?

        Rails.logger.info(
          message: 'VistA prescription affordances suppressed at Oracle Health stations',
          service: 'unified_health_data',
          source_system: 'vista',
          suppressed_count: suppressed.size,
          by_station: suppressed.map { |entry| entry[:station_number] }.tally,
          by_affordance: suppressed.map { |entry| entry[:affordance] }.tally,
          by_disp_status: suppressed.map { |entry| entry[:disp_status] }.tally
        )
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

      # Restores "Active: Refill in Process" for a VistA prescription whose requested refill has
      # been transmitted to CMOP but not yet dispensed. During that handoff VistA reports the
      # aggregate disp_status as plain "Active" (with is_refillable true), so a mid-fill med looks
      # idle. Only prescriptions still showing plain 'Active' are bridged, so upstream states such
      # as "Active: Shipped" or an already-restored "Active: Refill in Process" take precedence.
      # Gated to VistA only: Oracle Health surfaces its own in-process status correctly.
      #
      # This deliberately leaves is_refillable and
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
