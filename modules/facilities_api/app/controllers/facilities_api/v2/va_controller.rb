# frozen_string_literal: true

module FacilitiesApi
  class V2::VAController < ApplicationController
    include FacilitiesApi::V2::FacilitiesErrorHandler
    skip_before_action :verify_authenticity_token
    before_action :check_va_disabled
    before_action :validate_facility_id, only: :show

    # Facility ids are a 2-3 letter facility-type prefix (vha, vba, nca, vc),
    # an underscore, and a station number of up to 15 alphanumerics, hyphens,
    # and underscores (e.g. vha_402GA, nca_828-A)
    FACILITY_ID_REGEX = /\A[a-z]{2,3}_[a-z0-9_-]{1,15}\z/i

    def search
      params[:facilityIds] = params[:ids] if params[:ids].present?
      api_results = api.get_facilities(lighthouse_params)

      render_json(serializer, lighthouse_params, api_results)
    end

    def show
      api_result = api.get_by_id(params[:id])

      render_json(serializer, lighthouse_params, api_result)
    end

    private

    def check_va_disabled
      return unless Flipper.enabled?(:facility_locator_va_disabled)

      render json: {
        errors: [{ title: 'Service Unavailable', detail: 'VA facility search is temporarily unavailable', code: '503' }]
      }, status: :service_unavailable
    end

    def api
      FacilitiesApi::V2::Lighthouse::Client.new
    end

    def lighthouse_params
      params.permit(
        :ids,
        :facilityIds,
        :lat,
        :long,
        :mobile,
        :page,
        :per_page,
        :radius,
        :state,
        :type,
        :visn,
        :zip,
        bbox: [],
        services: []
      )
    end

    def serializer
      FacilitiesApi::V2::Lighthouse::FacilitySerializer
    end

    def resource_path(options)
      v2_va_search_url(options)
    end

    def mobile_api
      FacilitiesApi::V2::MobileCovid::Client.new
    end

    def mobile_api_get_by_id(id)
      mobile_api.direct_booking_eligibility_criteria_by_id(id).covid_online_scheduling_available?
    end

    def covid_mobile_params?
      lighthouse_params.fetch(:type, '')[/health/i] && lighthouse_params[:services]&.any?(/Covid19Vaccine/i)
    end

    def validate_facility_id
      raise Common::Exceptions::InvalidFieldValue.new('id', params[:id]) unless
        params[:id].to_s.match?(FACILITY_ID_REGEX)
    end
  end
end
