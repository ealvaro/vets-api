# frozen_string_literal: true

module V0
  module SignIn
    class OktaLogoutController < LogoutController
      private

      def client_id
        @client_id ||= IdentitySettings.sign_in.okta_client_id
      end

      def logout_event
        'okta logout'
      end

      def logout_success_statsd_key
        ::SignIn::Constants::Statsd::STATSD_SIS_OKTA_LOGOUT_SUCCESS
      end

      def logout_failure_statsd_key
        ::SignIn::Constants::Statsd::STATSD_SIS_OKTA_LOGOUT_FAILURE
      end
    end
  end
end
