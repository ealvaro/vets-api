# frozen_string_literal: true

module FacilitiesApi
  class V2::CcpController < ApplicationController
    include FacilitiesApi::V2::FacilitiesErrorHandler
    # DEPRECATED (2026-07): this generic `GET /facilities_api/v2/ccp?type=...` search appears
    # unused. vets-website's facility-locator only ever calls the dedicated member routes
    # (#provider, #pharmacy, #urgent_care, #specialties) — its config.js cannot emit a `type`
    # param against the ccp base URL. A 30-day Datadog review of `GET /facilities_api/v2/ccp`
    # found zero real-consumer traffic (only Anthropic DAST + crawler user-agents). The
    # deprecation_warning below exists to surface any genuine caller before this action, its
    # #ppms_search dispatcher, and the FacilityServiceLocator branches are removed.
    #
    # Provider supports the following query parameters:
    # @param bbox - Bounding box in form "xmin,ymin,xmax,ymax" in Lat/Long coordinates
    # @param services - Optional specialty services filter
    def index
      deprecation_warning

      api_results = ppms_search

      render_json(V2::PPMS::ProviderSerializer, ppms_params, api_results)
    end

    # This dedicated route searches PPMS via POSLocator, which is used for urgent care locations.
    def urgent_care
      api_results = api.pos_locator(ppms_action_params)

      render_json(V2::PPMS::ProviderSerializer, ppms_action_params, api_results)
    end

    # NOTE: this dedicated route searches PPMS via ProviderLocator (individual providers).
    # This is a DIFFERENT PPMS endpoint than the generic `index?type=provider` search, which
    # uses FacilityServiceLocator (see #ppms_search). "provider" here names the PPMS endpoint,
    # not the `type` filter value used by #index.
    # This is used when e.g. website selects CCP, then in type of care selects "urgent care" (POS)
    # or some other specialty type (provider locator).
    def provider
      api_results = if provider_urgent_care?
                      api.pos_locator(ppms_action_params)
                    else
                      api.provider_locator(ppms_provider_params)
                    end
      render_json(V2::PPMS::ProviderSerializer, ppms_action_params, api_results)
    end

    def pharmacy
      api_results = api.facility_service_locator(ppms_action_params.merge(specialties: ['3336C0003X']))

      render_json(V2::PPMS::ProviderSerializer, ppms_action_params, api_results)
    end

    def specialties
      api_results = api.specialties

      render_json(V2::PPMS::SpecialtySerializer, params, api_results)
    end

    private

    def api
      @api ||= FacilitiesApi::V2::PPMS::Client.new
    end

    def ppms_params
      params.require(:type)
      params.permit(
        :lat,
        :latitude,
        :long,
        :longitude,
        :page,
        :per_page,
        :radius,
        :type,
        specialties: []
      )
    end

    def ppms_action_params
      params.permit(
        :lat,
        :latitude,
        :long,
        :longitude,
        :page,
        :per_page,
        :radius,
        specialties: []
      )
    end

    def ppms_provider_params
      params.require(:specialties)
      params.permit(
        :lat,
        :latitude,
        :long,
        :longitude,
        :page,
        :per_page,
        :radius,
        :type,
        specialties: []
      )
    end

    # Generic CCP search dispatched from #index by the `type` query param.
    # NOTE: `type` is a caller-supplied filter value, NOT a PPMS endpoint name. Both the
    # 'provider' and 'pharmacy' types search PPMS via FacilityServiceLocator (facility-based
    # provider *services*). This is intentionally a different endpoint than the dedicated
    # #provider action, which uses ProviderLocator (individual providers). Don't assume
    # type == 'provider' maps to ProviderLocator.
    def ppms_search
      if urgent_care?
        api.pos_locator(ppms_params)
      elsif ppms_params[:type] == 'provider'
        api.facility_service_locator(ppms_provider_params)
      elsif ppms_params[:type] == 'pharmacy'
        api.facility_service_locator(ppms_params.merge(specialties: ['3336C0003X']))
      end
    end

    def urgent_care?
      (ppms_params[:type] == 'provider' && provider_urgent_care?) || ppms_params[:type] == 'urgent_care'
    end

    def provider_urgent_care?
      ppms_provider_params[:specialties] == ['261QU0200X']
    end

    def resource_path(options)
      v2_ccp_index_url(options)
    end

    # Logs any hit to the deprecated #index action so a genuine consumer (non-crawler) can be
    # identified before removal. See the deprecation note on #index. Safe to delete along with
    # #index, #ppms_search, #ppms_params, and #urgent_care? once traffic is confirmed dead.
    def deprecation_warning
      Rails.logger.info(
        'facilities_api.v2.ccp#index is deprecated and slated for removal',
        controller: 'FacilitiesApi::V2::CcpController',
        action: 'index',
        type: params[:type],
        user_agent: request.user_agent
      )
    end
  end
end
