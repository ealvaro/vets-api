# frozen_string_literal: true

module VAOS
  module V2
    module Unified
      ##
      # Maps CCRA referral +category_of_care+ values to the downstream formats
      # used by the unified scheduling flow:
      #
      # - +vaos_service_type+: the lowerCamelCase VAOS clinical service identifier
      #   passed to {EligibilityService#check_eligibility} and
      #   {VAOS::V2::SystemsService#get_facility_clinics}.
      # - +eps_nucc_specialty_ids+: NUCC Healthcare Provider Taxonomy codes passed
      #   to Wellhive's +ProviderService#search+ as the +specialtyId+ query param.
      # - +eps_name_match_patterns+: regexes used for an optional client-side
      #   post-filter on Wellhive results, matched against provider name, facility
      #   (location) name, and specialty names. Defense-in-depth on top of the NUCC
      #   server-side filter.
      #
      # CCRA returns +category_of_care+ as UPPER CASE free-text (e.g. "PRIMARY CARE"),
      # which does not directly match either Lighthouse's +serviceId+ vocabulary nor
      # Wellhive's NUCC-aligned specialty names. This mapper is the single source of
      # truth for that translation.
      #
      # ## Pilot defaulting strategy
      #
      # The unified scheduling pilot is currently scoped to PRIMARY CARE referrals.
      # Two layers protect that scoping:
      #
      # 1. Per-section PC fallback. When CCRA's value matches a known entry in
      #    {CCRA_TO_TARGETS}, that entry's fields win; any field the entry does
      #    NOT define falls back to {PRIMARY_CARE_DEFAULTS}. Entirely unmapped or
      #    blank categories also fall back to PC defaults. Every fallback emits a
      #    +Rails.logger.warn+ + StatsD increment so we can spot referrals being
      #    force-defaulted to PC and add the right mapping over time. Blank input
      #    is tagged +no_value+. VAOS rejects clinic lookups without a
      #    +clinicalService+ filter (HTTP 500), so a non-blank vaos_service_type
      #    is mandatory regardless.
      #
      # 2. Pilot kill-switch (+va_online_scheduling_unified_non_primary_care+).
      #    When DISABLED (default), every CCRA value is force-resolved to
      #    {PRIMARY_CARE_DEFAULTS} regardless of whether an explicit entry
      #    exists, scoping the pilot to PC routing end-to-end. Each override of
      #    a known non-PC entry emits a separate +pc_override+ log + counter so
      #    the routing decision is auditable. When the flag is ENABLED, the
      #    explicit entry wins (with per-section PC fallback for any missing
      #    fields). Callers must pass +user:+ for the flag to be evaluated;
      #    omitting +user:+ behaves as if the flag is enabled (used by
      #    backend-only paths and class-level convenience methods).
      #
      # ## Adding new entries
      #
      # New CCRA categories should be added to {CCRA_TO_TARGETS}. The entry MAY
      # omit any subset of the three downstream-target keys; missing keys
      # inherit from {PRIMARY_CARE_DEFAULTS} via per-section merge. Note that
      # +VAOS::V2::AppointmentsService::SCHEDULABLE_SERVICE_TYPES+ enumerates
      # which +vaos_service_type+ values VAOS will direct-schedule; entries
      # using values outside that list (e.g. +'urology'+) will route EPS
      # correctly but VAOS direct booking will likely 4xx. NUCC codes and name
      # patterns SHOULD be reviewed by clinical before adding new entries.
      #
      class CcraCategoryMapper
        STATSD_KEY_PREFIX = 'api.vaos.ccra_category_mapper'

        PILOT_PC_ONLY_FLAG = :va_online_scheduling_unified_non_primary_care

        # Pilot-wide default applied per-section when the CCRA category does not
        # supply a value for a given downstream target.
        # NUCC codes:
        #   207Q00000X - Family Medicine
        #   207R00000X - Internal Medicine
        #   208D00000X - General Practice
        PRIMARY_CARE_DEFAULTS = {
          vaos_service_type: 'primaryCare',
          eps_nucc_specialty_ids: %w[207Q00000X 207R00000X 208D00000X].freeze,
          eps_name_match_patterns: [
            /primary\s+care/i,
            /family\s+medicine/i,
            /internal\s+medicine/i,
            /general\s+practice/i
          ].freeze
        }.freeze

        # CCRA +category_of_care+ (normalized UPPER CASE) -> downstream targets.
        #
        # Starter table covering one-word/two-word categories we have authoritative
        # VAOS service-type mappings for (drawn from
        # +VAOS::V2::Unified::ServiceTypeMapper::LIGHTHOUSE_TO_VAOS+ and
        # +VAOS::V2::AppointmentsService::SCHEDULABLE_SERVICE_TYPES+) plus a few
        # common specialty referrals we expect to see in CCRA. NUCC codes
        # included for the most common specialties so EPS routing can work
        # immediately when the +PILOT_PC_ONLY_FLAG+ is enabled.
        #
        # NOTE: NUCC codes and name patterns should be reviewed by clinical
        # before being relied on in production. Entries marked with TODO need
        # clinical validation.
        CCRA_TO_TARGETS = {
          'PRIMARY CARE' => PRIMARY_CARE_DEFAULTS,

          # ---- VAOS direct-schedulable specialties (in SCHEDULABLE_SERVICE_TYPES) ----

          'AUDIOLOGY' => {
            vaos_service_type: 'audiology',
            # 231H00000X - Audiologist
            eps_nucc_specialty_ids: %w[231H00000X].freeze,
            eps_name_match_patterns: [/audiology/i, /audiologist/i, /hearing/i].freeze
          }.freeze,

          'OPTOMETRY' => {
            vaos_service_type: 'optometry',
            # 152W00000X - Optometrist
            eps_nucc_specialty_ids: %w[152W00000X].freeze,
            eps_name_match_patterns: [/optometry/i, /optometrist/i, /eye\s+care/i].freeze
          }.freeze,

          'OPHTHALMOLOGY' => {
            vaos_service_type: 'ophthalmology',
            # 207W00000X - Ophthalmology
            eps_nucc_specialty_ids: %w[207W00000X].freeze,
            eps_name_match_patterns: [/ophthalmology/i, /ophthalmologist/i].freeze
          }.freeze,

          'NUTRITION' => {
            vaos_service_type: 'foodAndNutrition',
            # 133V00000X - Dietitian, Registered
            eps_nucc_specialty_ids: %w[133V00000X].freeze,
            eps_name_match_patterns: [/nutrition/i, /dietitian/i, /dietetics/i].freeze
          }.freeze,

          'PHARMACY' => {
            vaos_service_type: 'clinicalPharmacyPrimaryCare',
            # 333600000X - Pharmacy (single specialty)
            eps_nucc_specialty_ids: %w[333600000X].freeze,
            eps_name_match_patterns: [/pharmacy/i, /pharmacist/i].freeze
          }.freeze,

          # ---- Common non-direct-schedulable specialties (EPS-routed) ----
          # vaos_service_type intentionally inherits +primaryCare+ from
          # {PRIMARY_CARE_DEFAULTS} via per-section merge: VAOS direct
          # scheduling doesn't support these clinical services, but EPS does
          # and that's where these referrals will route in practice.

          'CHIROPRACTIC' => {
            # 111N00000X - Chiropractor
            eps_nucc_specialty_ids: %w[111N00000X].freeze,
            eps_name_match_patterns: [/chiropractic/i, /chiropractor/i].freeze
          }.freeze,

          'PODIATRY' => {
            # 213E00000X - Podiatrist
            eps_nucc_specialty_ids: %w[213E00000X].freeze,
            eps_name_match_patterns: [/podiatry/i, /podiatrist/i, /foot\s+(and\s+ankle|care)/i].freeze
          }.freeze,

          'DERMATOLOGY' => {
            # 207N00000X - Dermatology
            eps_nucc_specialty_ids: %w[207N00000X].freeze,
            eps_name_match_patterns: [/dermatology/i, /dermatologist/i, /skin/i].freeze
          }.freeze,

          'CARDIOLOGY' => {
            # 207RC0000X - Internal Medicine, Cardiovascular Disease
            eps_nucc_specialty_ids: %w[207RC0000X].freeze,
            eps_name_match_patterns: [/cardiology/i, /cardiologist/i, /cardiovascular/i, /heart/i].freeze
          }.freeze,

          'UROLOGY' => {
            # 208800000X - Urology
            eps_nucc_specialty_ids: %w[208800000X].freeze,
            eps_name_match_patterns: [/urology/i, /urologist/i].freeze
          }.freeze
        }.freeze

        ##
        # Performs case-insensitive lookup, applies per-section PC fallback for
        # any missing fields, and logs once when a fallback or pilot override is
        # applied. This is the single entry point: call once per CCRA value and
        # destructure the result hash. Avoid wrapping per-key accessors -- each
        # +lookup+ call re-evaluates Flipper and (potentially) re-logs, which
        # would multiply log volume by the number of keys read.
        #
        # @param ccra_category [String, nil]
        # @param user [User, nil] optional. When provided AND the
        #   {PILOT_PC_ONLY_FLAG} flag is DISABLED for that user, an explicit
        #   non-PC entry is force-overridden to {PRIMARY_CARE_DEFAULTS} (with a
        #   +pc_override+ log + StatsD counter for auditability). When omitted,
        #   the explicit entry wins (backend paths without user context).
        # @return [Hash] always contains all three downstream-target keys
        #   (+:vaos_service_type+, +:eps_nucc_specialty_ids+,
        #   +:eps_name_match_patterns+); falls back to
        #   {PRIMARY_CARE_DEFAULTS} when CCRA category is unmapped, blank, or
        #   pilot is PC-only.
        #
        def self.lookup(ccra_category, user: nil)
          key = ccra_category.to_s.strip.upcase
          entry = key.empty? ? nil : CCRA_TO_TARGETS[key]

          log_unmapped(ccra_category) if entry.nil?

          merged = PRIMARY_CARE_DEFAULTS.merge(entry || {})

          if pilot_pc_only?(user) && merged != PRIMARY_CARE_DEFAULTS
            log_pc_override(ccra_category, merged)
            return PRIMARY_CARE_DEFAULTS
          end

          merged
        end

        # Pilot is PC-only when the +non_primary_care+ flag is DISABLED for the
        # given user. With no user we cannot evaluate the per-actor flag, so we
        # treat the call as "trust the table" (used by backend-only paths,
        # class-level convenience methods, and existing callers that haven't
        # been updated to pass +user:+).
        def self.pilot_pc_only?(user)
          return false if user.nil?

          !Flipper.enabled?(PILOT_PC_ONLY_FLAG, user)
        rescue => e
          # Fail open to PC routing on Flipper outages -- safer for the pilot
          # to over-route to PC than to surface a non-PC mapping when we can't
          # confirm the operator intended to enable it.
          Rails.logger.warn(
            "#{STATSD_KEY_PREFIX}.pilot_flag_check_failed",
            error_class: e.class.name, error_message: e.message
          )
          true
        end
        private_class_method :pilot_pc_only?

        def self.log_unmapped(ccra_category)
          sanitized = sanitize_for_log(ccra_category)
          Rails.logger.warn(
            'CcraCategoryMapper: unmapped category_of_care, defaulting to primaryCare',
            category_of_care: sanitized
          )
          StatsD.increment(
            "#{STATSD_KEY_PREFIX}.unmapped",
            tags: ["category_of_care:#{sanitized}"]
          )
        end
        private_class_method :log_unmapped

        # Logged when a known non-PC entry is force-overridden to PC defaults
        # because the pilot kill-switch is off. Distinct from +unmapped+ so
        # operators can tell "we have a mapping but the pilot is suppressing
        # it" apart from "we have no mapping at all".
        #
        # We log the suppressed NUCC ids alongside the suppressed VAOS service
        # type because for EPS-only entries (e.g. CARDIOLOGY, CHIROPRACTIC)
        # the +vaos_service_type+ is just the inherited +'primaryCare'+ default
        # and would otherwise look like the entry was identical to PC.
        def self.log_pc_override(ccra_category, suppressed_mapping)
          sanitized = sanitize_for_log(ccra_category)
          Rails.logger.warn(
            'CcraCategoryMapper: pilot is PC-only, overriding mapped category to primaryCare',
            category_of_care: sanitized,
            suppressed_vaos_service_type: suppressed_mapping[:vaos_service_type].to_s,
            suppressed_eps_nucc_specialty_ids: Array(suppressed_mapping[:eps_nucc_specialty_ids])
          )
          StatsD.increment(
            "#{STATSD_KEY_PREFIX}.pc_override",
            tags: ["category_of_care:#{sanitized}"]
          )
        end
        private_class_method :log_pc_override

        # Whitespace-stripped, underscore-joined tag value to match the codebase's
        # existing sanitize_log_value pattern (see referrals_controller, etc.).
        # Prevents StatsD tag values from containing spaces. Blank values are
        # surfaced as the literal string +"no_value"+ in tags/log payloads.
        def self.sanitize_for_log(value)
          return 'no_value' if value.blank?

          value.to_s.strip.gsub(/\s+/, '_')
        end
        private_class_method :sanitize_for_log
      end
    end
  end
end
