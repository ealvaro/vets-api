# frozen_string_literal: true

module SignIn
  class AuthorizeSSOContainer < Common::RedisStore
    redis_store REDIS_CONFIG[:sign_in_authorize_sso_container][:namespace]
    redis_ttl REDIS_CONFIG[:sign_in_authorize_sso_container][:each_ttl]
    redis_key :uuid

    attribute :uuid, String
    attribute :client_id, String
    attribute :code_challenge, String
    attribute :code_challenge_method, String
    attribute :client_state, String
    attribute :app_name, String
    attribute :nonce, String

    UUID_FORMAT = /\A\h{8}-\h{4}-\h{4}-\h{4}-\h{12}\z/

    validates :uuid, :client_id, presence: true
    validates :uuid, format: { with: UUID_FORMAT }

    def to_authorize_sso_params
      {
        client_id:,
        code_challenge:,
        code_challenge_method:,
        state: client_state,
        app_name:,
        nonce:
      }.compact
    end
  end
end
