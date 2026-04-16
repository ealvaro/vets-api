# frozen_string_literal: true

require 'sign_in/constants/auth'

module SignIn
  class Logger
    attr_reader :prefix

    def initialize(prefix:)
      @prefix = prefix
    end

    def info(message, context = {})
      Rails.logger.info("[SignInService] [#{prefix}] #{message}", context)
    end

    def error(message, exception:, context: {})
      error_code = extract_error_code(exception)

      payload = context.merge(
        errors: exception.message,
        error_code:
      )

      Rails.logger.info("[SignInService] [#{prefix}] #{message}", payload)
    end

    private

    def extract_error_code(exception)
      exception.try(:code) || SignIn::Constants::ErrorCode::INVALID_REQUEST
    end
  end
end
