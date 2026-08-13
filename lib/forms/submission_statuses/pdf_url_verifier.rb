# frozen_string_literal: true

require 'faraday'

module Forms
  module SubmissionStatuses
    class PdfUrlVerifier
      BREAKERS_SERVICE_NAME = 'SubmissionPdfS3'
      REQUEST_OPTIONS = { open_timeout: 15, timeout: 15 }.freeze

      CONNECTION = Faraday.new(request: REQUEST_OPTIONS) do |conn|
        conn.use(:breakers, service_name: BREAKERS_SERVICE_NAME)
        conn.adapter Faraday.default_adapter
      end

      def self.breakers_service
        matcher = proc do |breakers_service, _request_env, request_service_name|
          request_service_name == breakers_service.name
        end

        Breakers::Service.new(
          name: BREAKERS_SERVICE_NAME,
          request_matcher: matcher
        )
      end

      def self.connection
        CONNECTION
      end

      def exists?(url)
        self.class.connection.get(url).status == 200
      end
    end
  end
end
