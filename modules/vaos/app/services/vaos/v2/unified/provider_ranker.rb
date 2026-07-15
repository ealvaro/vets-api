# frozen_string_literal: true

module VAOS
  module V2
    module Unified
      ##
      # Deterministic, non-LLM provider ranking engine. Reorders a list of providers by a tunable
      # weighted score built from the signals already enriched onto each provider (proximity,
      # availability, and -- phase 2 -- continuity of care), and annotates each with a numeric
      # +match_score+ (0-100) and a human-readable +rationale+ generated from the same data.
      #
      # Pure and stateless: input is an array of {BaseProvider}s plus weights/caps; output is the
      # same providers sorted best-first with +match_score+ and +rationale+ set. No I/O, no upstream
      # calls -- unit-testable in isolation.
      #
      # == Absent signals are "unknown", not "zero"
      #
      # +distance_from_user+ is best-effort (silent +nil+ on Haversine failure) and
      # +next_available_date+ is frequently +nil+ (VA enrichment degrades silently; EPS enrichment
      # is Flipper-gated). A missing signal means "we don't know", not "this is bad" -- so each
      # provider is scored only on the factors it actually has, with the remaining weights
      # renormalized. A failed availability fetch therefore can't silently demote a nearby provider,
      # and missing data never becomes a false 100. The rationale mentions only real signals.
      #
      # VA and EPS lists are ranked separately (see {ProviderSearchService}), so scores are only
      # ever compared within a single care type -- weights/caps may differ per type.
      class ProviderRanker
        # Fallback weights/caps used when Settings omits a value. Weights need not sum to 1; they
        # are renormalized against whichever factors are present for a given provider.
        DEFAULT_WEIGHTS = { proximity: 0.45, availability: 0.45, continuity: 0.10 }.freeze
        DEFAULT_CAPS = { distance_miles: 60, wait_days: 30 }.freeze

        ##
        # @param weights [Hash] +{ proximity:, availability:, continuity: }+ relative factor weights
        # @param caps [Hash] +{ distance_miles:, wait_days: }+ normalization ceilings; values at or
        #   beyond the cap score 0 for that factor so one runaway value can't dominate
        # @param today [Date] reference date for the availability calculation (injectable for tests)
        #
        # Values are coerced to Float; nil/invalid entries are dropped so Settings/env string
        # overlays cannot overwrite defaults or TypeError during scoring.
        def initialize(weights: DEFAULT_WEIGHTS, caps: DEFAULT_CAPS, today: Date.current)
          @weights = DEFAULT_WEIGHTS.merge(coerce_numeric_hash(weights))
          @caps = DEFAULT_CAPS.merge(coerce_numeric_hash(caps))
          @today = today
        end

        ##
        # Annotates and reorders providers, best match first.
        #
        # @param providers [Array<BaseProvider>] candidates (already enriched with distance/availability)
        # @return [Array<BaseProvider>] same objects, +match_score+/+rationale+ set, sorted desc by score,
        #   then closer distance, then original input index (Array#sort_by is not stable; the index
        #   tiebreak makes exact ties deterministic for +recommended+ / list order)
        def rank(providers)
          list = Array(providers)
          list.each { |provider| annotate!(provider) }
          list.each_with_index
              .sort_by { |provider, index| [-provider.match_score, provider.distance_from_user || Float::INFINITY, index] }
              .map(&:first)
        end

        private

        # Settings / Parameter Store may hand us string keys, string numbers, or nils.
        # Keep only coercible numerics so merge never clobbers defaults with junk.
        def coerce_numeric_hash(raw)
          return {} unless raw.respond_to?(:to_h)

          raw.to_h.symbolize_keys.each_with_object({}) do |(key, value), acc|
            numeric = coerce_float(value)
            acc[key] = numeric unless numeric.nil?
          end
        end

        def coerce_float(value)
          return nil if value.nil?

          Float(value)
        rescue ArgumentError, TypeError
          nil
        end

        def annotate!(provider)
          factors = present_factors(provider)
          provider.match_score = weighted_score(factors)
          provider.rationale = build_rationale(factors)
          provider
        end

        # Builds the set of factors we actually have data for. Each entry carries its normalized
        # 0-100 value, its weight, and the rationale phrase to surface. Absent signals are omitted
        # entirely (not defaulted) so they neither help nor hurt the score.
        def present_factors(provider)
          {
            proximity: proximity_factor(provider),
            availability: availability_factor(provider),
            continuity: continuity_factor(provider)
          }.compact
        end

        def proximity_factor(provider)
          miles = provider.distance_from_user
          return nil if miles.blank?

          { value: inverse_scale(miles, @caps[:distance_miles]),
            weight: @weights[:proximity], phrase: "#{miles.round} mi away" }
        end

        def availability_factor(provider)
          days = days_until(provider.next_available_date)
          return nil if days.nil?

          { value: inverse_scale(days, @caps[:wait_days]),
            weight: @weights[:availability], phrase: availability_phrase(days) }
        end

        # Phase 2: continuity is only a factor once the appointment-history join has set the flag.
        # +seen_before+ nil = not joined / no join key (e.g. VA clinics have no NPI) = unknown.
        def continuity_factor(provider)
          return nil if provider.seen_before.nil?

          { value: provider.seen_before ? 100 : 0,
            weight: @weights[:continuity],
            phrase: (provider.seen_before ? 'seen here before' : nil) }
        end

        # Weighted average over ONLY the present factors, renormalized to their combined weight.
        # No factors (e.g. distance failed and availability never loaded) => 0 => bottom of list.
        def weighted_score(factors)
          total_weight = factors.sum { |_, factor| factor[:weight] }
          return 0.0 if total_weight.zero?

          weighted = factors.sum { |_, factor| factor[:value] * factor[:weight] }
          (weighted / total_weight).round(2)
        end

        # Maps "lower is better" quantities (miles, wait days) to a 0-100 score where closer/sooner
        # is higher. Clamped at +cap+ so a single extreme value can't swing the whole ranking.
        def inverse_scale(value, cap)
          return 0.0 if cap.to_f <= 0

          bounded = value.to_f.clamp(0, cap.to_f)
          (100 * (1 - (bounded / cap.to_f))).round(2)
        end

        def availability_phrase(days)
          case days
          when 0 then 'available today'
          when 1 then 'opens tomorrow'
          else "opens in #{days} days"
          end
        end

        # Whole days from +@today+ to the provider's next-available date. Returns nil (unknown) for a
        # blank or unparseable date so the factor is dropped rather than scored as zero. Past dates
        # clamp to 0.
        def days_until(date_string)
          return nil if date_string.blank?

          (Date.iso8601(date_string.to_s) - @today).to_i.clamp(0, nil)
        rescue ArgumentError, TypeError
          nil
        end

        def build_rationale(factors)
          factors.filter_map { |_, factor| factor[:phrase] }.join(' · ')
        end
      end
    end
  end
end
