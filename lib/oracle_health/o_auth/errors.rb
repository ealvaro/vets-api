# frozen_string_literal: true

module OracleHealth
  module OAuth
    module Errors
      class TokenError < Common::Client::Errors::ClientError; end

      class InvalidClientError < TokenError; end

      class InvalidScopeError < TokenError; end

      class ServiceUnavailableError < TokenError; end
    end
  end
end
