# frozen_string_literal: true

module VAOS
  module V2
    module Unified
      class ProviderSearchService
        include VAOS::CommunityCareConstants

        DEFAULT_RADIUS_MILES = 25
        STATSD_KEY_PREFIX = 'api.vaos.unified_provider_search'

        attr_reader :current_user

        def initialize(current_user)
          @current_user = current_user
        end

        ##
        # Searches for VA clinics (via Lighthouse facilities + VAOS clinics) and EPS CC providers
        # near the user's address, filtered by the referral's category of care. Pins the referral's
        # matched CC provider at the top, then sorts remaining results by distance.
        #
        # @param referral [Object] A CCRA referral object with category_of_care, provider NPI, etc.
        # @param radius [Integer] Search radius in miles (default: 25)
        # @return [Array<BaseProvider>] Combined, sorted provider list
        #
        def search(referral:, radius: DEFAULT_RADIUS_MILES)
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

          va_future = Concurrent::Promises.future do
            fetch_va_providers(user_address, referral, radius, lh_client:)
          end
          eps_future = Concurrent::Promises.future do
            fetch_eps_providers(user_address, referral, radius, eps_client:)
          end

          [va_future.value!, eps_future.value!]
        end

        def fetch_va_providers(user_address, referral, radius, lh_client:)
          facilities = lh_client.get_facilities(
            lat: user_address.latitude,
            long: user_address.longitude,
            radius:,
            type: 'health',
            per_page: 50
          )

          fetch_providers_for_facilities(facilities, referral, user_address)
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

        def fetch_providers_for_facilities(facilities, referral, user_address)
          matching_facilities = filter_supported_facilities(facilities, referral.category_of_care)
          clinical_service = ServiceTypeMapper.to_vaos(referral.category_of_care)

          matching_facilities.flat_map do |facility|
            fetch_clinics_for_facility(facility, clinical_service).map do |clinic|
              provider = VAProvider.from_facility_and_clinic(facility, clinic)
              assign_distance(provider, user_address)
              provider
            end
          end
        end

        def fetch_eps_providers(user_address, referral, radius, eps_client:)
          providers = eps_client.search_by_location(
            latitude: user_address.latitude,
            longitude: user_address.longitude,
            radius:,
            specialty: referral.category_of_care
          )

          (providers || []).map do |provider_hash|
            build_eps_provider_with_distance(provider_hash, user_address)
          end
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

        def filter_supported_facilities(facilities, category_of_care)
          return facilities if category_of_care.blank?

          vaos_service_type = ServiceTypeMapper.to_vaos(category_of_care)
          return facilities if vaos_service_type.nil?

          facilities.select do |facility|
            eligibility_service.check_eligibility(
              facility_id: facility.unique_id,
              category_of_care:
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
