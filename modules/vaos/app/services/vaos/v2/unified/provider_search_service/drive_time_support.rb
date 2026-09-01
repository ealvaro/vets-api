# frozen_string_literal: true

module VAOS
  module V2
    module Unified
      class ProviderSearchService
        # Shared core of the drive-time enrichment for the unified provider list, extracted from
        # {ProviderSearchService} to keep the service focused. Holds the pieces both sources share:
        # the enrichment kill switch, the parallel join orchestrator, the bounded future join,
        # coverage/timeout/failure logging, and numeric coercion. Every source fails open
        # independently -- an upstream failure leaves that source's fields absent.
        #
        # The per-source pipelines live alongside as sibling modules included next to this one:
        # {EpsDriveTimeSupport} (community-care providers, batched EPS +/drive-times+ call keyed
        # by coordinate) and {VADriveTimeSupport} (VA providers, one +/nearby+ call keyed by
        # facility id, drive-time bands collapsed to a midpoint).
        #
        # Nested lexically inside the class (rather than as a sibling module) so class
        # constants like +STATSD_KEY_PREFIX+ resolve via +Module.nesting+, and so the
        # methods can lean on the host's +eps_provider_service+, +lighthouse_nearby_client+,
        # +coerce_float+, +current_user+, +log_prefix+ and +@cached_user_uuid+ once included.
        module DriveTimeSupport
          # Fallback ceiling (seconds) for waiting on a drive-times future when
          # Settings.vaos.unified_scheduling.drive_time_timeout_seconds is unset or unparseable.
          DEFAULT_DRIVE_TIME_TIMEOUT_SECONDS = 8
          OUTER_JOIN_HEADROOM_SECONDS = 1

          # Cap on the number of unmatched provider ids sampled into the coverage log so a
          # fully-dropped page can't produce a runaway log line. The +missing_count+ is
          # always exact; +missing_ids+ is a bounded sample for spot-checking.
          MAX_LOGGED_MISSING_IDS = 50

          private

          # Kill switch for the drive-time enrichment (added upstream latency). Gates both
          # source calls -- the batched EPS /drive-times call and the VA Facilities /nearby
          # call -- so flipping it off drops the enrichment entirely and providers come back
          # with blank drive times rather than none at all.
          def drive_time_enrichment_enabled?
            Flipper.enabled?(:va_online_scheduling_unified_drive_time, current_user)
          end

          # Joins both drive-time futures concurrently. Waiting sequentially would let a slow
          # VA join consume the full drive_time_timeout_seconds before EPS even starts waiting;
          # running each bounded join on its own future lets the two waits overlap. When the pool
          # schedules both promptly they run concurrently, so in the good case the wall-clock wait
          # is ~one timeout rather than the two summed -- but that's a best case, not a guarantee:
          # the outer +.each { future.value!(deadline) }+ still applies the ceiling per waiter
          # sequentially (see the deadline note below). Each source fails open independently, and
          # the VA future touches only va_providers while the EPS future touches only eps_providers
          # (disjoint), so there's no shared-state race.
          #
          # The +deadline+ here is a per-waiter ceiling applied sequentially, not a ceiling on
          # the whole join: if neither waiter ever gets scheduled (starved pool / blocked apply)
          # this can wait up to 2x deadline before returning. That's the outer backstop, kept
          # deliberately loose so a slow-to-schedule pool still has a chance to land drive times
          # -- the tight bound is the inner per-source wait in {#join_drive_times_future}.
          def apply_drive_times_in_parallel!(va_providers, va_future, eps_providers, eps_future)
            deadline = drive_time_timeout_seconds + OUTER_JOIN_HEADROOM_SECONDS
            [
              Concurrent::Promises.future { apply_va_drive_times!(va_providers, va_future) },
              Concurrent::Promises.future { apply_eps_drive_times!(eps_providers, eps_future) }
            ].each { |future| future.value!(deadline) }
          end

          # Shared join for both sources: waits on the future (bounded), fails open on
          # timeout/error, then writes each provider's drive time by looking up the
          # per-provider key (coordinate for EPS, facility id for VA) in the resolved map.
          # +identify+ names the provider attribute logged for unmatched providers
          # (facility id for VA, provider id for EPS) -- see {#record_drive_time_coverage}.
          def apply_drive_times!(providers, future, source, identify:, &provider_key)
            return if future.nil?

            drive_times = join_drive_times_future(source, future)
            return if drive_times.nil?

            providers.each { |p| p.drive_time_in_seconds = drive_times[provider_key.call(p)] }
            record_drive_time_coverage(providers, source, identify)
          rescue => e
            log_drive_time_failure(e, source)
          end

          # Emits coverage signal for a successful (non-timeout) enrichment: how many providers
          # we tried to enrich vs. how many ended up without a drive time. Two counters (total +
          # missing) let Datadog chart a per-source missing ratio; when anything is missing we
          # also warn with a bounded sample of the unmatched provider ids (facility id for VA,
          # provider id for EPS -- both public identifiers, no PII/PHI) so the gap is diagnosable
          # -- e.g. VA facilities beyond the /nearby page falling out of the band map.
          def record_drive_time_coverage(providers, source, identify)
            StatsD.increment("#{STATSD_KEY_PREFIX}.drive_time_enrichment.provider_count", providers.size,
                             tags: ["source:#{source}"])

            missing = providers.reject(&:drive_time_in_seconds)
            return if missing.empty?

            StatsD.increment("#{STATSD_KEY_PREFIX}.drive_time_enrichment.missing", missing.size,
                             tags: ["source:#{source}"])
            log_drive_time_missing(source, missing, providers.size, identify)
          end

          def log_drive_time_missing(source, missing, provider_count, identify)
            Rails.logger.warn(
              "#{log_prefix}: drive-time enrichment incomplete",
              { source:,
                missing_count: missing.size,
                provider_count:,
                missing_ids: missing.map { |p| p.public_send(identify) }.uniq.first(MAX_LOGGED_MISSING_IDS),
                user_uuid: @cached_user_uuid }.compact
            )
          end

          # Bounded join of a drive-time future. Returns the resolved map, or nil when the
          # wait timed out -- value!(timeout) returns nil rather than raising or cancelling
          # the work, and both fetches always return a Hash, so a nil result means timeout.
          def join_drive_times_future(source, future)
            timeout = drive_time_timeout_seconds
            drive_times = StatsD.measure("#{STATSD_KEY_PREFIX}.drive_time_enrichment.wait.duration",
                                         tags: ["source:#{source}"]) do
              future.value!(timeout)
            end
            return drive_times unless drive_times.nil?

            log_drive_time_timeout(source, timeout)
            nil
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
