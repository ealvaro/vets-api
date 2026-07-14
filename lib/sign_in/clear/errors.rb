# frozen_string_literal: true

module SignIn
  module Clear
    module Errors
      class JWTDecodeError < StandardError; end
      class CodeVerifierNotFoundError < StandardError; end
    end
  end
end
