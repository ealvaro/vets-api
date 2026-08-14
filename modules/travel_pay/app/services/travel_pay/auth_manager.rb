# frozen_string_literal: true

module TravelPay
  class AuthManager
    include Monitorable

    def initialize(client_number, current_user)
      @user = current_user
      @client = TravelPay::TokenClient.new(client_number)
    end

    #
    # returns an AuthSession containing the veis_token & btsss_token
    #
    def authorize
      cached = TravelPayStore.find(@user.user_account_uuid)
      if cached
        monitor.log(:info, 'BTSSS tokens retrieved from cache',
                    request_id: RequestStore.store['request_id'])
        TravelPay::AuthSession.new(veis_token: cached.veis_token, btsss_token: cached.btsss_token,
                                   contact_id: cached.contact_id)
      else
        monitor.log(:info, 'BTSSS tokens not cached, requesting new tokens',
                    request_id: RequestStore.store['request_id'])

        request_new_tokens
      end
    end

    # Expose @user for consumers of the auth manager
    attr_reader :user

    private

    def request_new_tokens
      auth_session = @client.authorized_user_session(@user)
      if auth_session.btsss_token
        save_tokens!(@user.user_account_uuid, auth_session)
        monitor.log(:info, 'BTSSS tokens saved to cache',
                    request_id: RequestStore.store['request_id'])
        auth_session
      end
    end

    def save_tokens!(user_account_id, auth_session)
      token_record = TravelPayStore.new(
        user_account_id:,
        veis_token: auth_session.veis_token,
        btsss_token: auth_session.btsss_token,
        contact_id: auth_session.contact_id
      )
      token_record.save
    end

    def redis
      @redis ||= Redis::Namespace.new(REDIS_CONFIG[:travel_pay_store][:namespace], redis: $redis)
    end
  end
end
