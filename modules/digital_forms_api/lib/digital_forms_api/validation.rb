# frozen_string_literal: true

module DigitalFormsApi
  # validation functions
  module Validation
    module_function

    # retrieve and cache the openapi json from FormsAPI
    def openapi
      key = 'digital_forms_api:openapi'
      ttl = (Settings.digital_forms_api.cache_ttl.openapi.to_i || 5).minutes
      Rails.cache.fetch(key, expires_in: ttl, race_condition_ttl: 10.seconds) do
        require 'digital_forms_api/service/base'
        DigitalFormsApi::Service::Base.new.openapi
      end
    end

    # create and validate a submission request
    #
    # @see DigitalFormsApi::Service::Submissions#submit
    #
    # @param payload [Hash] validated form data
    # @param metadata [Hash] fields in addition to payload
    # @option metadata [String] :formId the form identifier, eg. '21-686c'; required
    # @option metadata [String] :veteranId the participant id of the veteran; required
    # @option metadata [String] :claimantId the participant id of the claimant; default to veteranId
    # @option metadata [String] :epCode the ep code; required
    # @option metadata [String] :claimLabel the claim label; required
    # @option metadata [String] :sourceRequestId the source identifier; optional
    #
    # @return [Mixed] valid value
    # @raise JSON::Schema::ValidationError
    def validate_submission_request(payload, metadata)
      transformed = {
        claimantId: { identifierType: 'PARTICIPANTID', value: metadata[:claimantId] || metadata[:veteranId] },
        veteranId: { identifierType: 'PARTICIPANTID', value: metadata[:veteranId] },
        payload:
      }

      request = { envelope: metadata.merge(transformed) }

      fragment = '#/components/schemas/submit-form-request'
      JSON::Validator.validate!(openapi, request, fragment:)

      request
    end

    # end Validation
  end
end
