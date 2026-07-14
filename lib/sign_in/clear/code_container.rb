# frozen_string_literal: true

module SignIn
  module Clear
    class CodeContainer < Common::RedisStore
      redis_store REDIS_CONFIG[:sign_in_clear_code_container][:namespace]
      redis_ttl REDIS_CONFIG[:sign_in_clear_code_container][:each_ttl]
      redis_key :state

      attribute :state, String
      attribute :code_verifier, String

      validates :state, presence: true
    end
  end
end
