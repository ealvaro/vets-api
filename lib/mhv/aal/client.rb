# frozen_string_literal: true

require 'common/client/base'
require 'common/client/concerns/mhv_session_based_client'
require 'mhv/aal/client_session'
require 'mhv/aal/configuration'
require 'mhv/aal/create_aal_form'

module AAL
  ##
  # Core class responsible for MHV Account Activity Log API interface operations
  #
  class Client < Common::Client::Base
    include Common::Client::Concerns::MHVSessionBasedClient

    ##
    # Create an AAL (account activity log) entry in MHV.
    #
    # @param [Hash] attributes - The AAL attributes to send
    # @param [Bool] once_per_session - Whether this log should be limited to once per session
    # @param [Vets::Type::UTCTime] session_id - Unique identifier for the user's VA.gov session, e.g. last_signed_in
    #
    def create_aal(attributes, once_per_session, session_id)
      return if once_per_session && already_logged_this_session?(attributes, session_id)

      attributes[:user_profile_id] = session.user_id.to_s
      form = AAL::CreateAALForm.new(attributes)
      perform(:post, 'usermgmt/activity', form.params, token_headers) if Flipper.enabled?(:mhv_enable_aal_integration)
    end

    ##
    # Retrieve paginated account activity logs from MHV.
    #
    # Query param keys are converted from snake_case to lowerCamelCase to match the
    # MHV AAL API contract (e.g. from_date -> fromDate, to_date -> toDate). Param
    # values are left untouched, and single-word keys (page, limit, sort, select,
    # style) are unaffected by the conversion.
    #
    # @param [ActionController::Parameters, Hash] params - Query parameters
    #   (from_date, to_date, page, limit, sort, select, style)
    # @return [Faraday::Response] the API response
    #
    def get_activities(params = {})
      query = params.respond_to?(:to_unsafe_h) ? params.to_unsafe_h : params.to_h
      query = query.transform_keys { |key| key.to_s.camelize(:lower) }
      perform(:get, 'usermgmt/external/activities', query, token_headers)
    end

    private

    def already_logged_this_session?(attributes, session_id)
      if session_id.blank?
        Rails.logger.warn('Skipping AAL per-session de-duplication: no session_id')
        return false
      end

      redis_key = aal_redis_key(attributes, session_id)
      return true if redis.exists?(redis_key)

      redis.set(redis_key, true, nx: false, ex: REDIS_CONFIG[log_store_config_key][:each_ttl])
      false
    end

    ##
    # Build a unique key for this AAL, based on the user, unique VA.gov session ID, and AAL
    # attributes. Only some attributes apply towards the unique fingerprint. For example,
    # completion_time is not included.
    #
    def aal_redis_key(attributes, session_id)
      base_hash = attributes
                  .except(:completion_time)
                  .to_h

      track_data = base_hash.merge(session_id:)

      fingerprint = Digest::SHA256.hexdigest(
        track_data.sort.to_h.to_json
      )

      "#{session.user_id}:#{fingerprint}"
    end

    def redis
      Redis::Namespace.new(REDIS_CONFIG[log_store_config_key][:namespace], redis: $redis)
    end

    ##
    # The REDIS_CONFIG key used for once-per-session de-duplication. Subclasses should
    # override this to use a client-specific namespace/TTL so that de-duplication does
    # not collide across MHV products (e.g. mobile vs. web) that may share the same
    # user_id and session_id.
    #
    def log_store_config_key
      :mhv_aal_log_store
    end

    ##
    # Overriding MHVSessionBasedClient's method to add x-api-key
    #
    def token_headers
      super.merge('x-api-key' => config.x_api_key)
    end

    ##
    # Overriding MHVSessionBasedClient's method to add x-api-key
    #
    def auth_headers
      super.merge('x-api-key' => config.x_api_key)
    end

    ##
    # Overriding MHVSessionBasedClient's method, because we need more control over the path.
    #
    def get_session_tagged
      perform(:get, 'usermgmt/auth/session', nil, auth_headers)
    end
  end

  class MRClient < Client
    include Common::Client::Concerns::MHVSessionBasedClient

    configuration AAL::MRConfiguration
    client_session AAL::MRClientSession

    def session_config_key
      :mhv_aal_mr_session_lock
    end

    def log_store_config_key
      :mhv_aal_mr_log_store
    end
  end

  class MobileClient < Client
    include Common::Client::Concerns::MHVSessionBasedClient

    configuration AAL::MobileConfiguration
    client_session AAL::MobileClientSession

    def session_config_key
      :mhv_aal_mobile_session_lock
    end

    def log_store_config_key
      :mhv_aal_mobile_log_store
    end
  end

  class RXClient < Client
    include Common::Client::Concerns::MHVSessionBasedClient

    configuration AAL::RXConfiguration
    client_session AAL::RXClientSession

    def session_config_key
      :mhv_aal_rx_session_lock
    end

    def log_store_config_key
      :mhv_aal_rx_log_store
    end
  end

  class SMClient < Client
    include Common::Client::Concerns::MHVSessionBasedClient

    configuration AAL::SMConfiguration
    client_session AAL::SMClientSession

    def session_config_key
      :mhv_aal_sm_session_lock
    end

    def log_store_config_key
      :mhv_aal_sm_log_store
    end
  end

  class AALClient < Client
    include Common::Client::Concerns::MHVSessionBasedClient

    configuration AAL::AALConfiguration
    client_session AAL::AALClientSession

    def session_config_key
      :mhv_aal_session_lock
    end
  end
end
