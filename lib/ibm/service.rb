# frozen_string_literal: true

require 'common/client/base'
require 'ibm/configuration'
require 'pdf_utilities/pdf_validator'

# IBM MMS API
module Ibm
  # Proxy Service for the IBM MMS API
  #
  # In addition to claims processing via the Lighthouse Benefits Intake API, which accepts PDFs,
  # the IBM MMS API accepts claims purely electronically, without rendering to PDF first.
  #
  # @see https://depo-platform-documentation.scrollhelp.site/developer-docs/endpoint-monitoring
  class Service < Common::Client::Base
    configuration Ibm::Configuration

    # tracking metric prefix
    STATSD_KEY_PREFIX = 'api.ibm_mms'

    attr_reader :location, :uuid

    # Perform the upload to IBM MMS
    #
    # @raise [JSON::ParserError] if form is not a valid JSON String
    # @raise [Common::Client::Errors::ClientError] if the upload request fails (connection
    #   error, non-2xx response, etc.). The error is logged with the guid and then re-raised
    #   so callers can detect the failure and decide how to react (retry, mark the submission
    #   failed, alert, etc.). Previously this method swallowed the error and returned the
    #   result of Rails.logger.error (`true`), which callers mistook for a successful upload.
    #
    # @param form [JSONString] form to be uploaded, must be valid JSON
    # @param guid [String] required guid for IBM MMS URL
    #
    # @return [Faraday::Response] the upstream response on success
    def upload_form(form:, guid:)
      form = JSON.parse(form)

      perform :put, upload_url(guid:), form.to_json, { 'Content-Type' => 'application/json' }
    rescue Common::Client::Errors::ClientError => e
      Rails.logger.error("IBM MMS Upload Error: #{e.message}", guid:)
      raise
    end

    def upload_url(guid:)
      "#{Ibm::Configuration.instance.service_path}/#{guid}"
    end

    # end Service
  end

  # end BenefitsIntake
end
