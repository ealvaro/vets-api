# frozen_string_literal: true

module Eps
  # Immutable value object describing the search criteria for
  # {Eps::ProviderService#search_by_location}. Groups the location, radius, and optional
  # specialty / self-schedulable filters into a single argument so the service method
  # doesn't take a long, easy-to-misorder keyword list.
  #
  # @!attribute [r] coordinates
  #   @return [Hash] search origin with +:latitude+ and +:longitude+ keys (Floats or numeric strings)
  # @!attribute [r] radius
  #   @return [Integer] maximum miles from the origin (default: 25)
  # @!attribute [r] specialty
  #   @return [String, nil] optional specialty name for client-side filtering (case-insensitive);
  #     ignored when +specialty_ids+ is provided
  # @!attribute [r] specialty_ids
  #   @return [Array<String>, nil] optional NUCC Healthcare Provider Taxonomy codes forwarded to
  #     Wellhive as +specialtyId+ for server-side filtering
  # @!attribute [r] self_schedulable_only
  #   @return [Boolean] when true (default), restricts results to self-schedulable (online-bookable)
  #     providers; when false, call-to-schedule (phone-only) providers are also returned
  ProviderSearchQuery = Data.define(
    :coordinates,
    :radius,
    :specialty,
    :specialty_ids,
    :self_schedulable_only
  ) do
    def initialize(coordinates:, radius: 25, specialty: nil, specialty_ids: nil, self_schedulable_only: true)
      super
    end
  end
end
