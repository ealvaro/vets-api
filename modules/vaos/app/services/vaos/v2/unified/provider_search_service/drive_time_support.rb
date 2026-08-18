# frozen_string_literal: true

module VAOS
  module V2
    module Unified
      class ProviderSearchService
        # Drive-time enrichment for the unified provider list, extracted from
        # {ProviderSearchService} to keep the service focused. Community-care (EPS/Wellhive)
        # providers get real drive times from one batched EPS +/drive-times+ call; VA
        # providers are an explicit no-op seam until the follow-up ticket. Every source
        # fails open independently -- an upstream failure leaves that source's fields absent.
        #
        # Nested lexically inside the class (rather than as a sibling module) so class
        # constants like +STATSD_KEY_PREFIX+ resolve via +Module.nesting+, and so the
        # methods can lean on the host's +eps_provider_service+, +coerce_float+,
        # +current_user+, +log_prefix+ and +@cached_user_uuid+ once included.
        module DriveTimeSupport
          # Fallback ceiling (seconds) for waiting on the EPS drive-times future when
          # Settings.vaos.unified_scheduling.drive_time_timeout_seconds is unset or unparseable.
          DEFAULT_DRIVE_TIME_TIMEOUT_SECONDS = 8

          private

          # Kill switch for the drive-time enrichment (added upstream latency). Gates the
          # batched EPS /drive-times call; VA drive times are not yet populated.
          def drive_time_enrichment_enabled?
            Flipper.enabled?(:va_online_scheduling_unified_drive_time, current_user)
          end

          # Kicks off the batched EPS /drive-times call as a future so it overlaps the
          # next-available enrichments; the caller joins it later via {#apply_eps_drive_times!}
          # so only latency beyond those enrichments hits the request. Returns nil (nothing
          # to join) when there are no EPS providers or the flag is off.
          def start_eps_drive_time_enrichment(eps_providers, user_address)
            return nil if eps_providers.blank?
            return nil unless drive_time_enrichment_enabled?

            Concurrent::Promises.future { fetch_drive_times_by_coordinates(eps_providers, user_address) }
          end

          def fetch_drive_times_by_coordinates(providers, user_address)
            coordinate_pairs = providers.map { |p| [coerce_float(p.latitude), coerce_float(p.longitude)] }
                                        .reject { |pair| pair.any?(&:nil?) }
                                        .uniq
            return {} if coordinate_pairs.empty?

            destinations = coordinate_pairs.each_with_index.to_h do |(latitude, longitude), i|
              ["d#{i}", { latitude:, longitude: }]
            end

            response = measure_drive_time_call(destinations, user_address)

            coordinate_pairs.each_with_index.to_h do |pair, i|
              seconds = response.destinations&.dig(:"d#{i}", :drive_time_in_seconds_without_traffic)
              [pair, coerce_integer(seconds)]
            end
          end

          def measure_drive_time_call(destinations, user_address)
            StatsD.measure("#{STATSD_KEY_PREFIX}.drive_time_call.duration",
                           tags: ["destination_count:#{destinations.size}", 'source:eps']) do
              eps_provider_service.get_drive_times(
                destinations:,
                origin: { latitude: user_address.latitude, longitude: user_address.longitude }
              )
            end
          end

          # VA drive times are deferred to a separate ticket. This explicitly leaves
          # drive_time_in_seconds nil so the payload shape stays stable (serializer omits
          # the driveTime keys). Signature keeps the future arg for the follow-up.
          def apply_va_drive_times!(va_providers, _future = nil)
            va_providers.each { |provider| provider.drive_time_in_seconds = nil }
          end

          def apply_eps_drive_times!(eps_providers, future)
            return if future.nil?

            timeout = drive_time_timeout_seconds
            drive_times = StatsD.measure("#{STATSD_KEY_PREFIX}.drive_time_enrichment.wait.duration",
                                         tags: ['source:eps']) do
              future.value!(timeout)
            end
            # value!(timeout) returns nil on timeout (it neither raises nor cancels the underlying
            # work); the fetch always returns a Hash, so a nil result here means we timed out.
            return log_drive_time_timeout('eps', timeout) if drive_times.nil?

            eps_providers.each do |provider|
              coordinates = [coerce_float(provider.latitude), coerce_float(provider.longitude)]
              provider.drive_time_in_seconds = drive_times[coordinates]
            end
          rescue => e
            log_drive_time_failure(e, 'eps')
          end

          # Settings-backed wait ceiling for the drive-times future, tunable via Parameter Store.
          # Float() so fractional seconds are allowed; falls back on non-positive or unparseable
          # config (mirrors ProviderSearchService.default_radius_miles, including its ops-visible
          # signal when the value can't be coerced -- otherwise a fat-fingered env var silently
          # pins the timeout at the default).
          def drive_time_timeout_seconds
            configured = Settings.vaos&.unified_scheduling&.drive_time_timeout_seconds
            value = Float(configured)
            value.positive? ? value : DEFAULT_DRIVE_TIME_TIMEOUT_SECONDS
          rescue ArgumentError, TypeError => e
            Rails.logger.warn(
              "#{STATSD_KEY_PREFIX}.drive_time_timeout_seconds.invalid_setting",
              fallback: DEFAULT_DRIVE_TIME_TIMEOUT_SECONDS,
              configured_class: configured.class.name,
              error_class: e.class.name
            )
            StatsD.increment("#{STATSD_KEY_PREFIX}.drive_time_timeout.invalid_setting",
                             tags: ["error_class:#{e.class.name}"])
            DEFAULT_DRIVE_TIME_TIMEOUT_SECONDS
          end

          def log_drive_time_failure(error, source)
            Rails.logger.warn(
              "#{log_prefix}: drive-time enrichment failed",
              { error_class: error.class.name, source:, user_uuid: @cached_user_uuid }.compact
            )
            StatsD.increment("#{STATSD_KEY_PREFIX}.drive_time_enrichment.failure", tags: ["source:#{source}"])
          end

          def log_drive_time_timeout(source, timeout_seconds)
            Rails.logger.warn(
              "#{log_prefix}: drive-time enrichment timed out",
              { source:, timeout_seconds:, user_uuid: @cached_user_uuid }.compact
            )
            StatsD.increment("#{STATSD_KEY_PREFIX}.drive_time_enrichment.timeout", tags: ["source:#{source}"])
          end

          # EPS sometimes returns numerics as strings (e.g. +distanceInMiles: '4'+),
          # so coerce drive-time seconds defensively rather than trusting the type.
          # Float-first parsing avoids Integer()'s octal reading of zero-padded
          # strings ('0420' -> 272) and accepts decimal strings ('420.5').
          def coerce_integer(value)
            coerce_float(value)&.round
          end
        end
      end
    end
  end
end
