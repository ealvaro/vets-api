# frozen_string_literal: true

module SignIn
  module OAuth
    module Errors
      class Error < StandardError; end
      class JWTVerificationError < Error; end
      class JWTExpiredError < Error; end
      class JWTDecodeError < Error; end
      class JWEDecodeError < Error; end
      class PublicJWKError < Error; end
      class CodeVerifierNotFoundError < Error; end
    end
  end
end
