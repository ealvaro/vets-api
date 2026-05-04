# frozen_string_literal: true

module GithubAuthentication
  class SessionUser
    attr_reader :login, :email, :name, :company

    def initialize(warden_user, org, team)
      @login = warden_user&.login
      @email = warden_user&.email
      @name = warden_user&.name
      @company = warden_user&.company
      @org_memberships = { org.to_s => warden_user&.organization_member?(org) }
      @team_memberships = { team.to_s => warden_user&.team_member?(team) }
    end

    def organization_member?(org)
      @org_memberships[org.to_s]
    end

    def team_member?(team)
      @team_memberships[team.to_s]
    end
  end
end
