# frozen_string_literal: true

module Common
  module Client
    # The error class defines the various error types that the client can encounter
    module Errors
      class Error < StandardError; end

      # Raised when a service is misconfigured, e.g. its base URL is not an
      # absolute URL (missing scheme or host). Surfacing this early gives a
      # clear, actionable message instead of a cryptic
      # `URI::BadURIError: both URI are relative` from deep inside Faraday.
      class ConfigurationError < Error; end

      class ClientError < Error
        attr_accessor :status, :body, :headers

        def initialize(message = nil, status = nil, body = nil, **hash)
          super(message)
          @status = status
          @body = body
          @headers = hash[:headers]
        end

        def response
          OpenStruct.new(status:, body:, headers:)
        end
      end

      class NotAuthenticated < ClientError; end
      class Serialization < ClientError; end
      class ParsingError < ClientError; end

      class HTTPError < ClientError
        def initialize(message = nil, status = nil, body = nil)
          super
        end

        alias code status
      end
    end
  end
end
