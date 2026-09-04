# frozen_string_literal: true

require 'lighthouse/benefits_reference_data/service'
module V0
  class BenefitsReferenceDataController < ApplicationController
    service_tag 'disability-application'

    # Faraday treats a `path` containing a scheme/host as an absolute URL and will
    # request it directly, ignoring the configured base URL (SSRF). Restrict to
    # simple slash-separated endpoint segments to prevent that.
    VALID_PATH_REGEX = %r{\A[a-zA-Z0-9\-_]+(/[a-zA-Z0-9\-_]+)*\z}

    def get_data
      validate_path!
      render json: benefits_reference_data_service
                   .get_data(path: params[:path], params: request.query_parameters).body
    end

    private

    def validate_path!
      return if params[:path].to_s.match?(VALID_PATH_REGEX)

      raise Common::Exceptions::InvalidFieldValue.new('path', params[:path])
    end

    def benefits_reference_data_service
      BenefitsReferenceData::Service.new
    end
  end
end
