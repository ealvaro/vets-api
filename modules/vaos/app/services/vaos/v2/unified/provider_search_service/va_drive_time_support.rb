# frozen_string_literal: true

module VAOS
  module V2
    module Unified
      class ProviderSearchService
        # VA drive-time pipeline: one origin-based VA Facilities +/nearby+ call keyed by
        # Lighthouse facility id, with coarse drive-time bands collapsed to a midpoint.
        # Kicked off as a future so it overlaps the next-available enrichments, then joined
        # via the shared {DriveTimeSupport} core. Leans on the host's +lighthouse_nearby_client+
        # and the shared +apply_drive_times!+ / +coerce_integer+ helpers once included.
        module VADriveTimeSupport
          private

          # Kicks off the VA Facilities /nearby call as a future, mirroring the EPS path so
          # it overlaps the next-available enrichments; the caller joins it later via
          # {#apply_va_drive_times!}. One origin-based call returns every nearby facility's
          # drive-time band, so unlike EPS the provider count doesn't affect the request.
          # Returns nil (nothing to join) when there are no VA providers or the flag is off.
          def start_va_drive_time_enrichment(va_providers, user_address)
            return nil if va_providers.blank?
            return nil unless drive_time_enrichment_enabled?

            Concurrent::Promises.future { fetch_va_drive_times_by_facility(user_address) }
          end

          # Joins the VA /nearby future and writes each provider's drive time, keyed by the
          # provider's Lighthouse facility id (matched against the band map). Providers whose
          # facility is absent (beyond the 90-minute nearby window) simply stay nil.
          def apply_va_drive_times!(va_providers, future)
            apply_drive_times!(va_providers, future, 'va', identify: :facility_id, &:facility_id)
          end

          # Single origin-based /nearby call -> { lighthouse_facility_id => seconds }.
          # nearby returns coarse drive-time bands (min/max minutes) per health facility
          # within 90 minutes of the origin; we collapse each to a midpoint in seconds.
          def fetch_va_drive_times_by_facility(user_address)
            facilities = measure_va_drive_time_call(user_address)
            facilities.each_with_object({}) do |facility, map|
              seconds = band_midpoint_seconds(facility.min_time, facility.max_time)
              map[facility.id] = seconds if seconds
            end
          end

          def measure_va_drive_time_call(user_address)
            StatsD.measure("#{STATSD_KEY_PREFIX}.drive_time_call.duration", tags: ['source:va']) do
              lighthouse_nearby_client.nearby(lat: user_address.latitude, long: user_address.longitude)
            end
          end

          # Midpoint of the drive-time band, in seconds. Using the midpoint (rather than the
          # min or max bound) keeps VA drive times comparable to EPS's point estimate, so
          # both sources rank and display on the same footing. Skips bands missing a bound.
          def band_midpoint_seconds(min_time, max_time)
            return nil if min_time.nil? || max_time.nil?

            coerce_integer(((min_time + max_time) / 2.0) * 60)
          end
        end
      end
    end
  end
end
