# frozen_string_literal: true

require 'sign_in/logger'

module SignIn
  module Webauthn
    class ApplicationController < SignIn::ApplicationController
      private

      def sign_in_logger
        @sign_in_logger ||= SignIn::Logger.new(prefix: 'SignIn::Webauthn')
      end
    end
  end
end
