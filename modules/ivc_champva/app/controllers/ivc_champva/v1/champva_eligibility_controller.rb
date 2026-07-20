# frozen_string_literal: true

require 'datadog'

module IvcChampva
  module V1
    class ChampvaEligibilityController < ApplicationController
      skip_after_action :set_csrf_header

      RATE_LIMIT_TTL = 30.minutes

      # Resolves VES eligibility for the applications behind the given form UUIDs.
      # Gated by a feature flag and a per-transaction rate limit.
      def update
        Datadog::Tracing.trace('IVC Champva Forms - ChampVA Eligibility Update') do
          return render_not_found unless feature_enabled?

          form_uuids = form_uuids_param
          return render_invalid_form_uuids unless valid_form_uuids?(form_uuids)

          transaction_uuid_map = transaction_uuid_map_for(form_uuids)
          transaction_uuids = transaction_uuid_map.keys

          retry_after = earliest_rate_limit(transaction_uuids)
          return render_rate_limited(retry_after) if retry_after

          enforce_rate_limit(transaction_uuids)
          results = eligibility_results(transaction_uuid_map)

          render json: { data: { results:, form_uuids: } }, status: :ok
        end
      rescue => e
        Rails.logger.error "Error in ChampVA eligibility update: #{e.message}"
        render json: { error_message: "Error: #{e.message}" }, status: :internal_server_error
      end

      private

      # @return [Boolean] whether the on-demand eligibility feature is enabled for the user
      def feature_enabled?
        Flipper.enabled?(:ivc_champva_ves_eligibility_on_demand, @current_user)
      end

      # Extracts the form_uuids array from the request body.
      #
      # @return [Object] the raw form_uuids value (validated by #valid_form_uuids?)
      def form_uuids_param
        JSON.parse(params.to_json)['form_uuids']
      end

      # @return [Boolean] whether form_uuids is a non-empty array
      def valid_form_uuids?(form_uuids)
        form_uuids.is_a?(Array) && form_uuids.any?
      end

      # Maps each transaction UUID to the requested form UUIDs that belong to it,
      # dropping forms that have no transaction UUID.
      #
      # @param form_uuids [Array<String>]
      # @return [Hash{String => Array<String>}]
      def transaction_uuid_map_for(form_uuids)
        IvcChampvaForm.where(form_uuid: form_uuids)
                      .pluck(:transaction_uuid, :form_uuid)
                      .each_with_object(
                        Hash.new { |hash, key| hash[key] = [] }
                      ) do |(transaction_uuid, form_uuid), hash|
          next if transaction_uuid.blank?

          hash[transaction_uuid] << form_uuid
        end
      end

      # Runs the eligibility service for each transaction UUID.
      #
      # @param transaction_uuid_map [Hash{String => Array<String>}]
      # @return [Array<Hash>] per-transaction service results
      def eligibility_results(transaction_uuid_map)
        transaction_uuid_map.map do |transaction_uuid, form_uuids|
          {
            transaction_uuid:,
            form_uuids:,
            **IvcChampva::ChampvaEligibilityService.new(transaction_uuid, form_uuids:).call
          }
        end
      end

      # Stamps a fresh rate-limit window on the forms for each transaction UUID
      # by recording the current VES fetch time.
      def enforce_rate_limit(transaction_uuids)
        # rubocop:disable Rails/SkipsModelValidations
        IvcChampvaForm.where(transaction_uuid: transaction_uuids)
                      .update_all(last_ves_fetch_at: Time.current)
        # rubocop:enable Rails/SkipsModelValidations
      end

      def render_not_found
        render json: { error_message: 'Not found' }, status: :not_found
      end

      def render_invalid_form_uuids
        render json: { error_message: 'form_uuids must be a non-empty array' }, status: :unprocessable_entity
      end

      def render_rate_limited(retry_after)
        response.set_header('Retry-After', retry_after.to_s)
        render json: { error_message: 'Rate limit exceeded. Please try again later.' }, status: :too_many_requests
      end

      # The smallest remaining rate-limit window (in seconds) across the given
      # transaction UUIDs, or nil when none are currently rate limited. A
      # transaction is rate limited when its most recent form fetch is still
      # within RATE_LIMIT_TTL.
      #
      # @return [Integer, nil]
      def earliest_rate_limit(transaction_uuids)
        now = Time.current
        IvcChampvaForm.where(transaction_uuid: transaction_uuids)
                      .where.not(last_ves_fetch_at: nil)
                      .group(:transaction_uuid)
                      .maximum(:last_ves_fetch_at)
                      .values
                      .filter_map do |last_fetch|
                        remaining = (last_fetch + RATE_LIMIT_TTL - now).to_i
                        remaining if remaining.positive?
                      end.min
      end
    end
  end
end
