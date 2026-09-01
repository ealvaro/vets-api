# frozen_string_literal: true

module VAOS
  module V2
    module Unified
      class ProviderSearchService
        # Community-care (EPS/Wellhive) drive-time pipeline: one batched EPS +/drive-times+
        # call keyed by destination coordinate. Kicked off as a future so it overlaps the
        # next-available enrichments, then joined via the shared {DriveTimeSupport} core.
        # Leans on the host's +eps_provider_service+, +coerce_float+ and the shared
        # +apply_drive_times!+ / +coerce_integer+ helpers once included.
        module EpsDriveTimeSupport
          private

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

          # Joins the EPS /drive-times future and writes each provider's drive time, keyed by
          # its [lat, long] coordinate pair (matched against the batched response map).
          def apply_eps_drive_times!(eps_providers, future)
            apply_drive_times!(eps_providers, future, 'eps', identify: :id) do |provider|
              [coerce_float(provider.latitude), coerce_float(provider.longitude)]
            end
          end
        end
      end
    end
  end
end
