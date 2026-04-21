# frozen_string_literal: true

module VAOS
  module V2
    module Unified
      class ProviderSearchService
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
          user_address = resolve_user_address
          unless user_address&.latitude && user_address.longitude
            raise Common::Exceptions::UnprocessableEntity.new(
              detail: 'User residential address with coordinates is required for provider search'
            )
          end

          va_providers, eps_providers = fetch_providers_in_parallel(
            user_address:, referral:, radius:
          )

          combine_and_sort(va_providers, eps_providers, referral)
        end

        private

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

        def fetch_eps_providers(user_address, radius, eps_client:, specialty_ids:, name_patterns:)
          providers = eps_client.search_by_location(
            latitude: user_address.latitude,
            longitude: user_address.longitude,
            radius:,
            specialty_ids: specialty_ids.presence
          )

          filtered = apply_name_filter(providers || [], name_patterns)

          filtered.map { |provider_hash| build_eps_provider_with_distance(provider_hash, user_address) }
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

          if va_providers.any? || eps_providers.any?
            StatsD.increment("#{STATSD_KEY_PREFIX}.search.success", tags: [
                               "va_count:#{va_providers.size}",
                               "eps_count:#{eps_providers.size}"
                             ])
          else
            StatsD.increment("#{STATSD_KEY_PREFIX}.search.no_results")
          end

          referral_provider ? [referral_provider] + sorted_others : sorted_others
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

        def log_prefix
          "#{CC_APPOINTMENTS}: Unified Provider Search"
        end
      end
    end
  end
end
