# frozen_string_literal: true

module Flipper
  class RouteAuthorizationConstraint
    def self.matches?(request)
      # Enforce org/team authorization for all mutating requests (POST, DELETE, PUT, PATCH).
      # This covers feature toggles, feature creation/deletion, import/export, and any future
      # mutating endpoints added by upstream gem updates.
      if %w[POST DELETE PUT PATCH].include?(request.method)
        return true if authorized?(request.session[:flipper_user])

        raise Common::Exceptions::Forbidden
      end

      # If Authenticated through GitHub, check authorization to determine what can be shown in views
      if request.session[:flipper_user].present?
        user = request.session[:flipper_user]
        RequestStore.store[:flipper_user_email_for_log] =
          user&.email || "Email not found for: #{user&.name || '<no name>'}, #{user&.company || '<no company>'}"
        RequestStore.store[:flipper_authorized] = authorized?(user)

        return true
      end

      # allow GET requests (minus the oauth/callback requests, which need to pass through to finish oauth workflow)
      return true if (
        request.method == 'GET' && request.path.exclude?('/callback') && request.params.exclude?('redirect')
      ) || Settings.flipper.github_oauth_key.blank?

      authenticate(request)
      true
    end

    def self.authenticate(request)
      RequestStore.store[:flipper_user_email_for_log] = nil
      warden = request.env['warden']
      warden.authenticate!(scope: :flipper)
    end

    def self.authorized?(user)
      return true if Settings.flipper.github_oauth_key.blank?

      org_name = Settings.flipper.github_organization
      team_id = Settings.flipper.github_team

      user&.organization_member?(org_name) && user.team_member?(team_id)
    end
  end
end
