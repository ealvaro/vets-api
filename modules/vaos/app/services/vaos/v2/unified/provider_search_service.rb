# frozen_string_literal: true

module VAOS
  module V2
    module Unified
      class ProviderSearchService # rubocop:disable Metrics/ClassLength
        include VAOS::CommunityCareConstants

        STATSD_KEY_PREFIX = 'api.vaos.unified_provider_search'
        # Hardcoded fallback when Settings.vaos.unified_scheduling.default_radius_miles
        # is unset, blank, or zero. AWS Parameter Store can override via the
        # +vaos__unified_scheduling__default_radius_miles+ env var.
        FALLBACK_RADIUS_MILES = 25

        attr_reader :current_user

        ##
        # Settings-backed default radius, tunable via AWS Parameter Store without a deploy.
        # Falls back to {FALLBACK_RADIUS_MILES} when the setting is missing, unparseable,
        # or non-positive (including zero and negatives). Guards against ops
        # misconfigurations where the Parameter Store value is empty, negative,
        # or a non-numeric string.
        #
        # @return [Integer]
        #
        def self.default_radius_miles
          configured = Settings.vaos&.unified_scheduling&.default_radius_miles
          value = Integer(configured)
          value.positive? ? value : FALLBACK_RADIUS_MILES
        rescue ArgumentError, TypeError => e
          # Emit an ops-visible signal when the Parameter-Store value can't be
          # coerced (e.g. +'25.0'+, +'abc'+, unexpected types). Without this the
          # fallback is silent and misconfigurations are invisible until
          # someone notices search radius isn't changing.
          Rails.logger.warn(
            "#{STATSD_KEY_PREFIX}.default_radius_miles.invalid_setting",
            fallback: FALLBACK_RADIUS_MILES,
            configured_class: configured.class.name,
            error_class: e.class.name
          )
          StatsD.increment(
            "#{STATSD_KEY_PREFIX}.default_radius_miles.invalid_setting",
            tags: ["error_class:#{e.class.name}"]
          )
          FALLBACK_RADIUS_MILES
        end

        def initialize(current_user)
          @current_user = current_user
        end

        ##
        # Searches for VA clinics (via Lighthouse facilities + VAOS clinics) and EPS CC providers
        # near the user's address, filtered by the referral's category of care. Pins the referral's
        # matched CC provider at the top, then sorts remaining results by distance.
        #
        # @param referral [Object] A CCRA referral object with category_of_care, provider NPI, etc.
        # @param radius [Integer] Search radius in miles (defaults to
        #   {.default_radius_miles}, which reads Settings)
        # @return [Array<BaseProvider>] Combined, sorted provider list
        #
        def search(referral:, radius: self.class.default_radius_miles)
          va_providers, eps_providers = fetch_and_enrich(referral:, radius:)
          combine_and_sort(va_providers, eps_providers, referral)
        end

        ##
        # Ranked variant of {#search}. VA and EPS providers are ranked *separately* (see
        # {ProviderRanker}) -- never merged into one list -- and returned as two groups so the
        # controller can emit them under distinct payload keys. The referral's matched CC provider
        # is still pinned to the top of the EPS group. Gated behind the
        # +unified_appointments_internal_provider_ranker+ Flipper flag at the controller.
        #
        # @param referral [Object] A CCRA referral object with category_of_care, provider NPI, etc.
        # @param radius [Integer] Search radius in miles (defaults to {.default_radius_miles})
        # @return [Hash{Symbol=>Array<BaseProvider>}] +{ va: [...], eps: [...] }+, each ranked best-first
        #
        def search_grouped(referral:, radius: self.class.default_radius_miles)
          va_providers, eps_providers = fetch_and_enrich(referral:, radius:)
          referral_provider, other_eps = partition_referral_provider(eps_providers, referral)

          record_search_result_metrics(va_providers, eps_providers)

          {
            va: mark_recommended(ranker(:va).rank(va_providers)),
            eps: mark_recommended(build_eps_group(referral_provider, other_eps))
          }
        end

        private

        # The referral's matched provider keeps the top slot but still runs through the ranker
        # (via a single-element rank) so it carries a match_score and rationale like its peers --
        # otherwise the pinned card would render with no explanation.
        def build_eps_group(referral_provider, other_eps)
          eps_ranker = ranker(:eps)
          ranked = eps_ranker.rank(other_eps)
          return ranked if referral_provider.nil?

          [*eps_ranker.rank([referral_provider]), *ranked]
        end

        # Flags the group's best-scoring provider (ties -> earliest in list) so the FE badges the
        # true best match. Position won't do: the pinned referral provider sits first regardless
        # of score, so "first in the group" and "best match" can be different providers.
        def mark_recommended(providers)
          best = providers.max_by(&:match_score)
          providers.each { |provider| provider.recommended = provider.equal?(best) }
        end

        # Shared pipeline for both {#search} and {#search_grouped}: resolve the user address, fetch
        # VA + EPS providers in parallel, then enrich each with next-available dates. Returns the two
        # raw (unsorted, unranked) provider lists.
        def fetch_and_enrich(referral:, radius:)
          user_address = resolve_user_address
          unless user_address&.latitude && user_address.longitude
            raise Common::Exceptions::UnprocessableEntity.new(
              detail: 'User residential address with coordinates is required for provider search'
            )
          end

          va_providers, eps_providers = fetch_providers_in_parallel(
            user_address:, referral:, radius:
          )

          StatsD.measure("#{STATSD_KEY_PREFIX}.va_next_available_enrichment.duration") do
            enrich_va_next_available!(va_providers)
          end
          StatsD.measure("#{STATSD_KEY_PREFIX}.eps_next_available_enrichment.duration") do
            enrich_eps_next_available!(eps_providers, referral)
          end

          [va_providers, eps_providers]
        end

        # Builds a {ProviderRanker} for the given care type (+:va+ or +:eps+) from Settings, so
        # product can tune "closer vs. sooner vs. same-clinic" per type without a deploy. Missing
        # config falls back to the ranker's own defaults.
        def ranker(type)
          cfg = Settings.vaos&.unified_scheduling&.ranking&.public_send(type)
          ProviderRanker.new(
            weights: cfg&.weights.to_h,
            caps: cfg&.caps.to_h
          )
        end

        def resolve_user_address
          current_user.vet360_contact_info&.residential_address
        end

        def fetch_providers_in_parallel(user_address:, referral:, radius:)
          @cached_user_uuid = current_user.uuid
          lh_client = lighthouse_client
          eps_client = eps_provider_service
          # Always run the CCRA mapper. Unmapped/blank categories fall back to
          # PRIMARY CARE per-section (with logging) so VAOS+Wellhive always get
          # a non-blank category filter -- VAOS otherwise returns 500 on
          # +/vpg/v1/locations/{id}/clinics+ when no clinicalService is sent.
          # Passing +user:+ lets the mapper consult the
          # +va_online_scheduling_unified_non_primary_care+ pilot kill-switch,
          # which (when DISABLED) overrides explicit non-PC entries to PC
          # routing for the duration of the pilot.
          mapping = CcraCategoryMapper.lookup(referral.category_of_care, user: current_user)
          clinical_service = mapping[:vaos_service_type]
          specialty_ids = mapping[:eps_nucc_specialty_ids]
          name_patterns = mapping[:eps_name_match_patterns]

          va_future = Concurrent::Promises.future do
            fetch_va_providers(user_address, radius, lh_client:, clinical_service:)
          end
          eps_future = Concurrent::Promises.future do
            fetch_eps_providers(user_address, radius, eps_client:, specialty_ids:, name_patterns:)
          end

          [va_future.value!, eps_future.value!]
        end

        def fetch_va_providers(user_address, radius, lh_client:, clinical_service:)
          facilities = lh_client.get_facilities(
            lat: user_address.latitude,
            long: user_address.longitude,
            radius:,
            type: 'health',
            per_page: 50
          )

          apply_vaos_station_ids!(facilities)
          facilities = apply_pilot_station_allowlist(facilities)

          fetch_providers_for_facilities(facilities, user_address, clinical_service:)
        rescue => e
          Rails.logger.error("#{log_prefix}: VA facility search failed",
                             {
                               error_class: e.class.name,
                               key: e.try(:key),
                               original_status: e.try(:original_status),
                               user_uuid: @cached_user_uuid
                             }.compact)
          StatsD.increment("#{STATSD_KEY_PREFIX}.va_search.failure")
          []
        end

        # Pilot scope: when an allowlist is configured (typically prod via the
        # +vaos__unified_scheduling__allowed_parent_stations+ env var), drop facilities
        # whose parent station isn't in the list. No-op when unset/blank (staging,
        # dev, test). Operates on the VAOS-facing +unique_id+ produced by
        # {#apply_vaos_station_ids!} so satellite suffixes (+"983GC"+) roll up to the
        # correct parent. Logs the rejected count so pilot scope is observable.
        def apply_pilot_station_allowlist(facilities)
          return facilities unless ParentStationFilter.enabled?

          allowed, rejected = facilities.partition { |f| ParentStationFilter.allowed?(f.unique_id) }
          if rejected.any?
            StatsD.increment(
              "#{STATSD_KEY_PREFIX}.station_allowlist.filtered",
              rejected.size,
              tags: ["allowed:#{ParentStationFilter.allowed_parents.join('|')}"]
            )
          end
          allowed
        end

        # Lighthouse returns production station IDs in every env; VAOS staging
        # expects mock IDs (983/984). Mutate each facility's +unique_id+ once here
        # so eligibility, clinic fetch, and +VAProvider.location_id+ all read the same
        # VAOS-facing station without wrapper types or per-call-site translation.
        # Composite Lighthouse +id+ is left unchanged; only +unique_id+ drives VAOS.
        # In production {FacilityIdTranslator.to_staging} is a no-op, so attributes
        # are unchanged.
        def apply_vaos_station_ids!(facilities)
          facilities.each do |facility|
            vaos_station_id = FacilityIdTranslator.to_staging(facility.unique_id)
            next if vaos_station_id == facility.unique_id

            facility.unique_id = vaos_station_id
          end
        end

        def fetch_providers_for_facilities(facilities, user_address, clinical_service:)
          matching_facilities = filter_supported_facilities(facilities, clinical_service)

          matching_facilities.flat_map do |facility|
            fetch_clinics_for_facility(facility, clinical_service).map do |clinic|
              provider = VAProvider.from_facility_and_clinic(
                facility, clinic,
                service_type: clinical_service
              )
              assign_distance(provider, user_address)
              provider
            end
          end
        end

        # Window (in days from today) used when asking VPG for each VA clinic's
        # earliest open slot. Mirrors what the FE used to fan out per-clinic.
        NEXT_AVAILABLE_WINDOW_DAYS = 90

        ##
        # For every VA provider in +va_providers+, attempt to populate
        # +next_available_date+ (YYYY-MM-DD in the clinic's local offset) by calling
        # +VAOS::V2::SystemsService#get_next_available_slots+ once per VistA site
        # with the full set of clinic IENs at that site. Calls fan out in parallel
        # across sites. Per-clinic failures, per-site failures, and missing
        # +start+ values all degrade silently to +nil+ -- the FE renders blank in
        # that case. Mutates the providers in place.
        def enrich_va_next_available!(va_providers)
          return if va_providers.blank?

          start_date = Time.current.utc.iso8601
          end_date = (Time.current.utc + NEXT_AVAILABLE_WINDOW_DAYS.days).iso8601

          providers_by_location = va_providers.group_by(&:location_id)
          futures = providers_by_location.map do |location_id, location_providers|
            Concurrent::Promises.future do
              [location_id, fetch_next_available_for_site(location_id, location_providers, start_date, end_date)]
            end
          end

          next_available_by_location = resolve_next_available_futures(futures)

          va_providers.each do |provider|
            provider.next_available_date = next_available_by_location.dig(provider.location_id, provider.id.to_s)
          end
        end

        def resolve_next_available_futures(futures)
          futures.to_h(&:value!)
        rescue => e
          Rails.logger.warn(
            "#{log_prefix}: next-available enrichment failed",
            { error_class: e.class.name, user_uuid: @cached_user_uuid }.compact
          )
          StatsD.increment("#{STATSD_KEY_PREFIX}.next_available_enrichment.failure")
          {}
        end

        # Returns a Hash mapping clinic IEN (String) -> ISO8601 date String for the
        # earliest available slot, omitting any clinic that didn't return a usable
        # slot. On any upstream/parse failure returns +{}+ so the providers just
        # render with blank dates.
        def fetch_next_available_for_site(location_id, location_providers, start_date, end_date)
          clinic_ids = location_providers.map { |p| p.id.to_s }.uniq
          slots = systems_service.get_next_available_slots(
            location_id:,
            clinic_ids:,
            on_or_after: start_date,
            before: end_date
          )
          build_clinic_date_map(slots)
        rescue => e
          log_next_available_failure(location_id, e)
          {}
        end

        def build_clinic_date_map(slots)
          Array(slots).each_with_object({}) do |slot, acc|
            next unless slot.respond_to?(:status) && slot.status.to_s == 'success'

            has_avail = slot.try(:has_availability)
            next unless has_avail == true || has_avail.to_s.casecmp('true').zero?

            start_value = slot.try(:start)
            next if start_value.blank?

            date_string = parse_date_string(start_value)
            acc[slot.clinic_id.to_s] = date_string if date_string
          end
        end

        def log_next_available_failure(location_id, error)
          Rails.logger.warn(
            "#{log_prefix}: next-available-slot fetch failed for site #{location_id}",
            { error_class: error.class.name, user_uuid: @cached_user_uuid }.compact
          )
          StatsD.increment("#{STATSD_KEY_PREFIX}.next_available_slot.failure")
        end

        # Preserves the clinic's local date (no UTC shift) by parsing the offset
        # in the upstream ISO8601 string and converting to a Date in that offset.
        # Logs on parse failure (rather than silently degrading) so STG can
        # surface upstream date-format regressions before they go unnoticed.
        def parse_date_string(value)
          Time.iso8601(value.to_s).to_date.iso8601
        rescue ArgumentError, TypeError => e
          Rails.logger.warn(
            "#{log_prefix}: next-available slot start could not be parsed as ISO8601",
            { error_class: e.class.name, user_uuid: @cached_user_uuid }.compact
          )
          StatsD.increment("#{STATSD_KEY_PREFIX}.next_available_date_parse.failure")
          nil
        end

        # POC: gated EPS slot polling. ONE draft per +(uuid, referral_number)+
        # is reused for slot queries across all candidate providers on the
        # referral; Wellhive ties slots to +appointmentId+, not to provider id.
        # Flag off -> FE renders "Schedule to view availability".
        def enrich_eps_next_available!(eps_providers, referral)
          return if eps_providers.blank?
          return unless Flipper.enabled?(:va_online_scheduling_unified_eps_next_available, current_user)

          referral_number = referral.try(:referral_number)
          return if referral_number.blank?

          draft_id = resolve_eps_draft_id(referral_number)
          return if draft_id.blank?

          # Only online-schedulable providers have self-schedulable appointment types/slots. Phone-only
          # (call-to-schedule) providers would raise in first_self_schedulable_appointment_type_id! and
          # inflate the ...eps_next_available_slot.failure metric, so skip them -- they correctly keep a
          # blank next_available_date.
          schedulable_providers = eps_providers.select(&:online_scheduling?)
          return if schedulable_providers.blank?

          start_date = Time.current.utc.iso8601
          end_date = (Time.current.utc + NEXT_AVAILABLE_WINDOW_DAYS.days).iso8601
          futures = schedulable_providers.map do |provider|
            Concurrent::Promises.future do
              [provider.id.to_s, fetch_next_available_for_eps_provider(provider, draft_id, start_date, end_date)]
            end
          end
          next_available_by_provider = resolve_eps_next_available_futures(futures)
          schedulable_providers.each { |p| p.next_available_date = next_available_by_provider[p.id.to_s] }
        end

        # Prefers a cached draft from an earlier slots step; on miss, mints one
        # and writes it back so a later submit reuses it instead of orphaning.
        def resolve_eps_draft_id(referral_number)
          redis = Eps::RedisClient.new
          cached = redis.fetch_draft_appointment_id(uuid: current_user.uuid, referral_number:)
          return cached if cached.present?

          draft_id = eps_appointment_service.create_draft_appointment(referral_id: referral_number)&.id
          return nil if draft_id.blank?

          redis.store_draft_appointment_id(
            uuid: current_user.uuid, referral_number:, draft_appointment_id: draft_id
          )
          draft_id
        rescue => e
          log_eps_draft_resolution_failure(e)
          nil
        end

        def fetch_next_available_for_eps_provider(provider, draft_id, start_date, end_date)
          appointment_type_id = provider.first_self_schedulable_appointment_type_id!
          response = eps_provider_service.get_provider_slots(
            provider.provider_service_id.presence || provider.id,
            appointmentTypeId: appointment_type_id,
            startOnOrAfter: start_date,
            startBefore: end_date,
            appointmentId: draft_id
          )
          slots = Array(response&.slots).map { |slot| EpsSlot.from_eps_slot(slot) }
          # CC providers need ~3 business days to accept and prep for a
          # referral, and Wellhive doesn't enforce that floor. Without
          # filtering, the "next available" surfaced on the provider list
          # disagrees with the slot picker, which already drops the same
          # near-term slots in slots_service.rb.
          earliest_eps_slot_date(CCLeadTimeFilter.filter(slots))
        rescue => e
          log_eps_next_available_failure(provider, e)
          nil
        end

        def earliest_eps_slot_date(slots)
          starts = Array(slots).map(&:start).compact_blank
          return nil if starts.empty?

          parse_date_string(starts.min)
        end

        def resolve_eps_next_available_futures(futures)
          futures.to_h(&:value!)
        rescue => e
          Rails.logger.warn(
            "#{log_prefix}: EPS next-available enrichment failed",
            { error_class: e.class.name, user_uuid: @cached_user_uuid }.compact
          )
          StatsD.increment("#{STATSD_KEY_PREFIX}.eps_next_available_enrichment.failure")
          {}
        end

        def log_eps_next_available_failure(provider, error)
          Rails.logger.warn(
            "#{log_prefix}: EPS next-available-slot fetch failed for provider #{provider.id}",
            { error_class: error.class.name, user_uuid: @cached_user_uuid }.compact
          )
          StatsD.increment("#{STATSD_KEY_PREFIX}.eps_next_available_slot.failure")
        end

        def log_eps_draft_resolution_failure(error)
          Rails.logger.warn(
            "#{log_prefix}: EPS draft resolution failed for next-available enrichment",
            { error_class: error.class.name, user_uuid: @cached_user_uuid }.compact
          )
          StatsD.increment("#{STATSD_KEY_PREFIX}.eps_draft_resolution.failure")
        end

        def fetch_eps_providers(user_address, radius, eps_client:, specialty_ids:, name_patterns:)
          # When enabled, also surface providers that can only be scheduled by phone
          # (call-to-schedule). When off, behavior is unchanged -- self-schedulable providers only.
          call_to_schedule = call_to_schedule_providers_enabled?
          query = build_eps_search_query(user_address, radius, specialty_ids, call_to_schedule)
          providers = eps_client.search_by_location(query)

          apply_name_filter(providers || [], name_patterns)
            .map { |provider_hash| build_eps_provider_with_distance(provider_hash, user_address) }
            .tap { |eps_providers| log_non_online_scheduling_count(eps_providers) if call_to_schedule }
        rescue => e
          Rails.logger.error("#{log_prefix}: EPS provider search failed",
                             {
                               error_class: e.class.name,
                               key: e.try(:key),
                               original_status: e.try(:original_status),
                               user_uuid: @cached_user_uuid
                             }.compact)
          StatsD.increment("#{STATSD_KEY_PREFIX}.eps_search.failure")
          []
        end

        def build_eps_search_query(user_address, radius, specialty_ids, call_to_schedule)
          Eps::ProviderSearchQuery.new(
            coordinates: { latitude: user_address.latitude, longitude: user_address.longitude },
            radius:,
            specialty_ids: specialty_ids.presence,
            self_schedulable_only: !call_to_schedule
          )
        end

        # Client-side regex post-filter applied to raw Wellhive provider hashes.
        # Gated by the +unified_name_filter+ Flipper flag (operational kill
        # switch on the regex post-filter only). The +patterns.blank?+ guard
        # is defensive: CcraCategoryMapper.lookup now always returns non-empty
        # patterns (PC defaults), but a future mapping change shouldn't crash.
        def apply_name_filter(provider_hashes, patterns)
          return provider_hashes if patterns.blank?
          return provider_hashes unless Flipper.enabled?(:va_online_scheduling_unified_name_filter, current_user)

          provider_hashes.select { |hash| provider_matches_patterns?(hash, patterns) }
        end

        # True when ANY pattern matches ANY of the provider's name-like fields:
        # top-level +name+, nested +location.name+, or any +specialties[].name+.
        def provider_matches_patterns?(provider_hash, patterns)
          return false if provider_hash.blank?

          candidate_names = [
            provider_hash[:name],
            provider_hash.dig(:location, :name),
            *Array(provider_hash[:specialties]).map { |s| s.is_a?(Hash) ? s[:name] : nil }
          ].compact

          patterns.any? { |pattern| candidate_names.any? { |n| n.to_s.match?(pattern) } }
        end

        def build_eps_provider_with_distance(provider_hash, user_address)
          provider = VAOS::V2::Unified::EpsProvider.from_eps_provider_service(provider_hash)
          provider.distance_from_user = distance_between_miles(
            user_address.latitude,
            user_address.longitude,
            provider.latitude,
            provider.longitude
          )
          provider
        end

        def assign_distance(provider, user_address)
          provider.distance_from_user = distance_between_miles(
            user_address.latitude,
            user_address.longitude,
            provider.latitude,
            provider.longitude
          )
        end

        # +vaos_service_type+ is the already-mapped VAOS clinical service identifier
        # (e.g. +"primaryCare"+) produced by {CcraCategoryMapper.lookup}.
        # The mapper always returns a non-blank value (PC default for unmapped /
        # blank CCRA categories), so the +blank?+ guard here is defensive only.
        # Facilities are already adjusted by {#apply_vaos_station_ids!} so
        # +unique_id+ matches what VAOS expects in this environment.
        def filter_supported_facilities(facilities, vaos_service_type)
          return facilities if vaos_service_type.blank?

          facilities.select do |facility|
            eligibility_service.check_eligibility(
              facility_id: facility.unique_id,
              vaos_service_type:
            )[:direct_eligible]
          end
        end

        def fetch_clinics_for_facility(facility, clinical_service)
          systems_service.get_facility_clinics(
            location_id: facility.unique_id,
            clinical_service:
          )
        rescue => e
          Rails.logger.warn(
            "#{log_prefix}: Clinic fetch failed for facility #{facility.unique_id}",
            {
              error_class: e.class.name,
              clinical_service:,
              user_uuid: @cached_user_uuid
            }.compact
          )
          []
        end

        def systems_service
          @systems_service ||= VAOS::V2::SystemsService.new(current_user)
        end

        def eligibility_service
          @eligibility_service ||= EligibilityService.new(current_user)
        end

        def combine_and_sort(va_providers, eps_providers, referral)
          referral_provider, other_eps = partition_referral_provider(eps_providers, referral)

          sorted_others = (va_providers + other_eps).sort_by do |p|
            p.distance_from_user || Float::INFINITY
          end

          record_search_result_metrics(va_providers, eps_providers)

          referral_provider ? [referral_provider] + sorted_others : sorted_others
        end

        def record_search_result_metrics(va_providers, eps_providers)
          if va_providers.any? || eps_providers.any?
            StatsD.increment("#{STATSD_KEY_PREFIX}.search.success", tags: [
                               "va_count:#{va_providers.size}",
                               "eps_count:#{eps_providers.size}"
                             ])
          else
            StatsD.increment("#{STATSD_KEY_PREFIX}.search.no_results")
          end
        end

        def partition_referral_provider(eps_providers, referral)
          referral_npi = referral.respond_to?(:provider_npi) ? referral.provider_npi : nil
          return [nil, eps_providers] if referral_npi.blank?

          matched = eps_providers.find { |p| p.npi == referral_npi }
          others = eps_providers.reject { |p| p == matched }

          [matched, others]
        end

        def distance_between_miles(lat1, lon1, lat2, lon2)
          lat1f = coerce_float(lat1)
          lon1f = coerce_float(lon1)
          lat2f = coerce_float(lat2)
          lon2f = coerce_float(lon2)
          return nil if [lat1f, lon1f, lat2f, lon2f].any?(&:nil?)

          rad_per_deg = Math::PI / 180.0
          earth_radius_miles = 3958.8
          dlat = (lat2f - lat1f) * rad_per_deg
          dlon = (lon2f - lon1f) * rad_per_deg
          lat1_rad = lat1f * rad_per_deg
          lat2_rad = lat2f * rad_per_deg

          a = (Math.sin(dlat / 2)**2) +
              (Math.cos(lat1_rad) * Math.cos(lat2_rad) * (Math.sin(dlon / 2)**2))
          c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a))
          earth_radius_miles * c
        end

        def coerce_float(value)
          Float(value)
        rescue ArgumentError, TypeError
          nil
        end

        def lighthouse_client
          @lighthouse_client ||= FacilitiesApi::V2::Lighthouse::Client.new
        end

        def eps_provider_service
          @eps_provider_service ||= Eps::ProviderService.new(current_user)
        end

        def eps_appointment_service
          @eps_appointment_service ||= Eps::AppointmentService.new(current_user)
        end

        # Flag gating the call-to-schedule (non-online-scheduling) provider enhancements:
        # surfacing phone-only providers and emitting the +onlineScheduling+ indicator.
        def call_to_schedule_providers_enabled?
          Flipper.enabled?(:va_online_scheduling_cc_direct_scheduling_v2_post_mvp, current_user)
        end

        # Emits a metric for how many EPS providers in the list are phone-only (call-to-schedule)
        # vs. online-schedulable, so we can observe adoption/volume of the post-MVP enhancement.
        def log_non_online_scheduling_count(eps_providers)
          phone_only = eps_providers.count { |p| !p.online_scheduling? }
          return if phone_only.zero?

          StatsD.increment("#{STATSD_KEY_PREFIX}.eps_non_online_scheduling.count", phone_only)
          Rails.logger.info(
            "#{log_prefix}: surfaced #{phone_only} call-to-schedule (phone-only) provider(s)",
            { phone_only:, eps_total: eps_providers.size, user_uuid: @cached_user_uuid }.compact
          )
        end

        def log_prefix
          "#{CC_APPOINTMENTS}: Unified Provider Search"
        end
      end
    end
  end
end
