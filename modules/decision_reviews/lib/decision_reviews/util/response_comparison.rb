# frozen_string_literal: true

module DecisionReviews
  module Util
    ##
    # Compares two API response bodies and reports how they differ, for validating a replacement
    # API against the one it is replacing: call both, compare, and decide whether the new response
    # is safe to serve.
    #
    # Response bodies routinely contain PII/PHI, so this class exposes only counts, booleans, and
    # key names -- never anything derived from a *value*. Every reader is therefore safe to log.
    #
    #   comparison = DecisionReviews::Util::ResponseComparison.new(
    #     expected: old_api_response.body,
    #     actual: new_api_response.body,
    #     ignored_keys: %w[type],
    #     ignore_order: true
    #   )
    #   comparison.equivalent?  # => true
    #   comparison.to_h         # => { expected_count: 7, actual_count: 7, ... }
    #
    # Assumes a JSON:API-shaped body: a collection member (`data` by default) holding an array of
    # records, alongside any number of other top-level members.
    #
    class ResponseComparison
      DEFAULT_COLLECTION_KEY = 'data'

      ##
      # @param expected [Hash] body from the API being replaced -- the baseline
      # @param actual [Hash] body from the candidate API
      # @param ignored_keys [Array<String>] key names dropped before comparing, **at every depth**.
      #   Each entry is a difference the comparison stops noticing, so keep the list short.
      # @param ignore_order [Boolean] when true, the collection is compared as a set: two responses
      #   listing the same records in a different sequence are equivalent. Only the collection is
      #   affected; arrays nested inside a record always compare in order.
      # @param collection_key [String] the top-level member holding the array of records
      #
      def initialize(expected:, actual:, ignored_keys: [], ignore_order: false,
                     collection_key: DEFAULT_COLLECTION_KEY)
        @expected = expected
        @actual = actual
        @ignored_keys = Array(ignored_keys).map(&:to_s)
        @ignore_order = ignore_order
        @collection_key = collection_key.to_s
      end

      ##
      # Whether the two responses say the same thing. Every value is compared, recursively, except
      # for `ignored_keys`; ordering is significant unless `ignore_order` was set.
      #
      def equivalent?
        same_non_collection_members? && comparable_records(expected) == comparable_records(actual)
      end

      ##
      # Whether the two responses hold the same records in a different sequence. Reported
      # independently of `ignore_order`: with the flag on it tells you the swap reordered something,
      # with it off it distinguishes a resequencing from a genuine data difference.
      #
      def ordering_differs?
        records_in_order(expected) != records_in_order(actual) &&
          sorted_records(expected) == sorted_records(actual)
      end

      def expected_count
        records(expected).count
      end

      def actual_count
        records(actual).count
      end

      ##
      # Key names that appear in one side's records but not the other's, at any depth, sorted.
      # These come from the response schema rather than from Veteran data, so they are safe to log
      # and are usually the quickest way to tell a structural difference from a data difference.
      #
      def differing_keys
        (key_names(expected) ^ key_names(actual)).sort
      end

      def to_h
        {
          expected_count:,
          actual_count:,
          differing_keys:,
          ordering_differs: ordering_differs?
        }
      end

      private

      attr_reader :expected, :actual, :ignored_keys, :ignore_order, :collection_key

      def records(body)
        collection = body.try(:[], collection_key)
        collection.is_a?(Array) ? collection : []
      end

      ##
      # Whether the responses agree on everything that is not the collection: which top-level
      # members are present, and the value of every member other than the collection itself.
      #
      # Usually a no-op, since most paired APIs return only the collection. Checked anyway, because
      # a member added to one API and not the other is exactly the kind of difference that should
      # stop a caller from treating the two as interchangeable.
      #
      def same_non_collection_members?
        return expected == actual unless expected.is_a?(Hash) && actual.is_a?(Hash)

        expected.keys.sort == actual.keys.sort &&
          canonicalize(expected.except(collection_key)) == canonicalize(actual.except(collection_key))
      end

      def comparable_records(body)
        ignore_order ? sorted_records(body) : records_in_order(body)
      end

      def records_in_order(body)
        records(body).map { |record| canonicalize(without_ignored_keys(record)) }
      end

      ##
      # The records in a stable order, so two responses listing them differently compare equal.
      # `canonicalize` deep-sorts hash keys, which is what makes `to_json` a usable sort key.
      #
      def sorted_records(body)
        records_in_order(body).sort_by(&:to_json)
      end

      def without_ignored_keys(value)
        case value
        when Hash then value.except(*ignored_keys).transform_values { |nested| without_ignored_keys(nested) }
        when Array then value.map { |nested| without_ignored_keys(nested) }
        else value
        end
      end

      def key_names(body)
        records(body).flat_map { |record| nested_key_names(without_ignored_keys(record)) }.to_set
      end

      def nested_key_names(value)
        case value
        when Hash then value.keys + value.values.flat_map { |nested| nested_key_names(nested) }
        when Array then value.flat_map { |nested| nested_key_names(nested) }
        else []
        end
      end

      ##
      # Recursively sorts hash keys so that serialization is stable.
      #
      def canonicalize(value)
        case value
        when Hash then value.sort.to_h.transform_values { |nested| canonicalize(nested) }
        when Array then value.map { |nested| canonicalize(nested) }
        else value
        end
      end
    end
  end
end
