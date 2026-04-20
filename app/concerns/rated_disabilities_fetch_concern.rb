# frozen_string_literal: true

require 'evss/disability_compensation_auth_headers'
require 'disability_compensation/factories/api_provider_factory'

# Shared logic for building a rated-disabilities API provider and fetching
# rated disabilities with optional retry and Breakers circuit-breaker awareness.
# Included by both FormProfiles::VA526ez and V0::DisabilityCompensationFormsController,
# both of which already include RetriableConcern (which provides #with_retries).
module RatedDisabilitiesFetchConcern
  extend ActiveSupport::Concern

  # Builds a Lighthouse-backed rated-disabilities API provider for +current_user+.
  #
  # @param current_user [User]
  # @return [LighthouseRatedDisabilitiesProvider]
  def rated_disabilities_api_provider(current_user)
    auth_headers = EVSS::DisabilityCompensationAuthHeaders.new(current_user)
                                                          .add_headers(EVSS::AuthHeaders.new(current_user).to_h)
    ApiProviderFactory.call(
      type: ApiProviderFactory::FACTORIES[:rated_disabilities],
      provider: :lighthouse,
      options: { icn: current_user.icn.to_s, auth_headers: },
      current_user:,
      feature_toggle: nil
    )
  end

  # Fetches rated disabilities via +api_provider+, optionally wrapping the
  # call in retry logic controlled by the
  # +:disability_compensation_retry_lh_rating_requests+ Flipper flag.
  #
  # When the flag is enabled and the VeteranVerification Breakers circuit is
  # open, raises +Breakers::OutageException+ rather than calling the provider,
  # so callers can surface a 503 through the global exception handler.
  #
  # @param api_provider [#get_rated_disabilities] provider instance
  # @param invoker      [String] caller label used in log messages
  # @param current_user [User]   used for Flipper flag evaluation
  def fetch_rated_disabilities_response(api_provider, invoker, current_user)
    unless Flipper.enabled?(:disability_compensation_retry_lh_rating_requests, current_user)
      return api_provider.get_rated_disabilities(nil, nil, { invoker: })
    end

    # VeteranVerification::Configuration is the Breakers circuit used by
    # VeteranVerification::Service, which LighthouseRatedDisabilitiesProvider wraps.
    lh_breakers_service = VeteranVerification::Configuration.instance.breakers_service
    if (lh_outage = lh_breakers_service.latest_outage).nil? || lh_outage.ended?
      with_retries(invoker, on: [Common::Exceptions::Timeout]) do
        api_provider.get_rated_disabilities(nil, nil, { invoker: })
      end
    else
      Rails.logger.warn('Skipping get_rated_disabilities due to service outage', { invoker: })
      raise Breakers::OutageException.new(lh_outage, lh_breakers_service)
    end
  end
end
