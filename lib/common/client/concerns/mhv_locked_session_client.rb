# frozen_string_literal: true

module Common
  module Client
    module Concerns
      ##
      # Module mixin for overriding session logic when making session-based client connections that
      # should lock during session creation, to prevent threads from making simultaneous
      # authentication API calls.
      #
      # All references to "session" in this module refer to the upstream MHV session.
      #
      # @see MedicalRecords::Client
      #
      # @!attribute [r] session
      #   @return [Hash] a hash containing session information
      #
      module MhvLockedSessionClient
        extend ActiveSupport::Concern

        LOCK_RETRY_DELAY = 0.3 # Number of seconds to wait between attempts to acquire a session lock
        RETRY_ATTEMPTS = 40 # How many times to attempt await of acquiring a session lock by a preceding request

        attr_reader :session

        ##
        # @param session [Hash] a hash containing a key with which the session will be found or built
        #
        def initialize(session:)
          refresh_session(session)
        end

        ##
        # Ensure the upstream MHV session is not expired or incomplete.
        #
        # @return [MhvFhirSessionClient] instance of `self`
        #
        def authenticate
          validate_user_key

          iteration = 0

          # Loop unless a complete, valid MHV session exists, or until max_iterations is reached
          while invalid?(@session) && iteration < RETRY_ATTEMPTS
            break if lock_and_get_session

            sleep(LOCK_RETRY_DELAY)

            # Refresh the MHV session reference in case another thread has updated it.
            refresh_session(@session)
            iteration += 1

            # Another thread may have created a valid session while we waited.
            break unless invalid?(@session)
          end
          if invalid?(@session) && iteration >= RETRY_ATTEMPTS
            Rails.logger.info("Failed to create #{@client_session} after #{iteration} attempts to acquire lock")
          end

          self
        end

        ##
        # Override client_session method to use extended ::ClientSession classes.
        # Subclasses must call `client_session SomeSession` to register their session class
        # before any instance is created, otherwise authenticate will fail.
        #
        class_methods do
          ##
          # @return [MedicalRecords::ClientSession] if a MR (Medical Records) client session
          # @return [Rx::ClientSession] if an Rx (Prescription) client session
          # @return [SM::ClientSession] if a SM (Secure Messaging) client session
          #
          def client_session(klass = nil)
            @client_session ||= klass
          end
        end

        protected

        def refresh_session(session)
          @session = self.class.client_session.find_or_build(session)
        end

        def invalid?(session)
          session.expired?
        end

        private

        def validate_user_key
          return if user_key.present?

          log_details = {
            session_class: self.class.client_session.try(:name),
            session_user_id_present: session.respond_to?(:user_id) && session.user_id.present?,
            session_icn_present: session.respond_to?(:icn) && session.icn.present?,
            session_user_uuid_present: session.respond_to?(:user_uuid) && session.user_uuid.present?
          }
          statsd_prefix = self.class.const_get(:STATSD_KEY_PREFIX) if self.class.const_defined?(:STATSD_KEY_PREFIX)
          StatsD.increment("#{statsd_prefix}.authenticate.user_key_missing") if statsd_prefix
          Rails.logger.error('MHV session creation failed: user_key is blank', log_details)
          raise Common::Exceptions::Forbidden,
                detail: 'Unable to access MHV services. Required user identification is missing.'
        end

        ##
        # Attempt to acquire a redis lock, then create a new MHV session. Once the session is created,
        # release the lock.
        #
        # return [Boolean] true if a session was created, otherwise false
        #
        def lock_and_get_session
          if obtain_redis_lock
            begin
              @session = get_session
              return true
            ensure
              release_redis_lock
            end
          end
          false
        end

        def redis_lock_config
          @redis_lock_config ||= REDIS_CONFIG[session_config_key]
        end

        def redis_lock_namespace
          @redis_lock_namespace ||= Redis::Namespace.new(redis_lock_config[:namespace], redis: $redis)
        end

        def lock_key
          "mhv_session_lock:#{user_key}"
        end

        def obtain_redis_lock
          redis_lock_namespace.set(lock_key, 1, nx: true, ex: redis_lock_config[:each_ttl])
        end

        def release_redis_lock
          redis_lock_namespace.del(lock_key)
        end
      end
    end
  end
end
