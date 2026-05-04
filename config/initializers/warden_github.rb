# frozen_string_literal: true

require 'github_authentication/session_user'

module WardenGithubStrategyExtensions
  def authenticate!
    Rails.logger.info do
      "[warden_github] authenticate! scope=#{scope} path=#{request.path} " \
        "sidekiq_user_present=#{session[:sidekiq_user].present?} " \
        "coverband_user_present=#{session[:coverband_user].present?} " \
        "flipper_user_present=#{session[:flipper_user].present?}"
    end

    if scope == :sidekiq && session[:sidekiq_user].present?
      success!(session[:sidekiq_user])
      redirect!(request.url)
    elsif scope == :coverband && session[:coverband_user].present?
      success!(session[:coverband_user])
      redirect!(request.url)
    else
      super
    end
  end

  def begin_flow!
    # We want this redirect value for later in the flow
    if request.path.include?('/flipper')
      Rails.logger.info { "[warden_github] begin_flow! flipper request url=#{request.env['QUERY_STRING']}" }
      redirect = request.env['QUERY_STRING']&.split('=')&.[](1)
      custom_session[:redirect] = redirect if redirect.present?
    end

    super
  end

  def finalize_flow!
    warden_user = load_user
    session[:sidekiq_user] = build_session_user(warden_user, :sidekiq) if scope == :sidekiq
    session[:coverband_user] = build_session_user(warden_user, :coverband) if scope == :coverband
    if scope == :flipper
      session[:flipper_user] = build_session_user(warden_user, :flipper)
      return_to = custom_session['return_to']
      Rails.logger.info { "[warden_github] finalize_flow! flipper return_to=#{return_to.inspect}" }
      if return_to
        url = return_to.split('?').first
        url += "/#{custom_session[:redirect]}" if custom_session[:redirect]
        custom_session['return_to'] = url
      end
    end

    super
  rescue => e
    Rails.logger.error("[warden_github] scope=#{scope}", exception: e)
    raise
  end

  private

  def build_session_user(warden_user, scope)
    scope_settings = Settings.public_send(scope)
    org = scope_settings&.github_organization
    team = scope_settings&.github_team

    Rails.logger.info(
      "[warden_github] build_session_user scope=#{scope} " \
      "warden_user_nil=#{warden_user.nil?} " \
      "scope_settings_nil=#{scope_settings.nil?} " \
      "org_nil=#{org.nil?} team_nil=#{team.nil?} " \
      "login_nil=#{warden_user&.login.nil?} email_nil=#{warden_user&.email.nil?} " \
      "name_nil=#{warden_user&.name.nil?} company_nil=#{warden_user&.company.nil?}"
    )

    GithubAuthentication::SessionUser.new(warden_user, org, team)
  end
end

Warden::GitHub::Strategy.module_eval do
  prepend WardenGithubStrategyExtensions
end
