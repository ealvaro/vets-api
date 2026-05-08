# frozen_string_literal: true

module Eps
  # Eps::RedisClient provides a caching mechanism for EPS appointment data.
  # It stores and retrieves appointment IDs for background processing.
  class RedisClient
    extend Forwardable

    attr_reader :settings

    # Cache keys and namespaces
    CACHE_KEY = 'vaos_eps_appointment'
    CACHE_NAMESPACE = 'eps-appointments'

    # 26 hours to be available for the full duration of the Eps::AppointmentStatusEmailJob retries
    # which will span approximately 25 hours.
    CACHE_TTL = 26.hours

    # Sized to the typical "select-slot then confirm" UX window, plus headroom
    # for a user who momentarily steps away. Long enough to absorb a normal
    # booking flow; short enough that drafts created during one session don't
    # linger after a user abandons the flow. Wellhive holds drafts for hours
    # on their side regardless, so a short Redis TTL just means we mint a new
    # draft on resume rather than reusing a stale one.
    DRAFT_CACHE_KEY = 'vaos_eps_draft'
    DRAFT_CACHE_TTL = 15.minutes

    # Initializes the RedisClient with settings.
    #
    # @return [Eps::RedisClient] A new instance of RedisClient
    def initialize
      @settings = REDIS_CONFIG[:eps_appointments]
    end

    # Store appointment status check data
    # Data is encrypted using Lockbox before storing to protect PII (email addresses)
    #
    # @param uuid [String] User's UUID
    # @param appointment_id [String] The appointment ID
    # @param email [String] User's email for notifications
    # @raise [ArgumentError] If required parameters are missing
    # @return [Boolean] True if the cache operation was successful
    def store_appointment_data(uuid:, appointment_id:, email:)
      raise ArgumentError, 'User UUID is required' if uuid.blank?
      raise ArgumentError, 'Appointment ID is required' if appointment_id.blank?
      raise ArgumentError, 'Email is required' if email.blank?

      cache_key = generate_appointment_data_key(uuid, appointment_id)
      data = { appointment_id:, email: }
      encrypted_data = encrypt_data(data)

      Rails.cache.write(
        cache_key,
        encrypted_data,
        namespace: CACHE_NAMESPACE,
        expires_in: CACHE_TTL
      )
    end

    # Retrieve appointment status check data from cache
    # Data is decrypted after retrieval using Lockbox
    # If decryption fails (old unencrypted data), returns nil (cache miss)
    #
    # @param uuid [String] User's UUID
    # @param appointment_id [String] The appointment ID
    # @return [Hash, nil] Appointment data if found and successfully decrypted
    def fetch_appointment_data(uuid:, appointment_id:)
      return if uuid.blank? || appointment_id.blank?

      cache_key = generate_appointment_data_key(uuid, appointment_id)
      encrypted_data = Rails.cache.read(cache_key, namespace: CACHE_NAMESPACE)
      return nil unless encrypted_data

      decrypt_data(encrypted_data)
    end

    # Cache a Wellhive draft appointment id under +(uuid, referral_number)+
    # so the unified booking flow can reuse the draft created during the
    # slots fetch instead of minting a second one at submit time. Skips the
    # write (rather than raising) when any input is blank -- the draft id is
    # an optimization, never load-bearing on correctness, so a missing input
    # should degrade to the no-cache path silently.
    #
    # Draft ids are short opaque tokens, not PII; not encrypted (in contrast
    # to {#store_appointment_data}, which holds the user's email).
    #
    # @param uuid [String] User's UUID
    # @param referral_number [String] CCRA referral identifier (e.g. "VA0000007419")
    # @param draft_appointment_id [String] Wellhive draft id from
    #   {Eps::AppointmentService#create_draft_appointment}
    # @return [Boolean] +true+ on successful write, +false+ when any input is blank
    def store_draft_appointment_id(uuid:, referral_number:, draft_appointment_id:)
      return false if uuid.blank? || referral_number.blank? || draft_appointment_id.blank?

      Rails.cache.write(
        generate_draft_key(uuid, referral_number),
        draft_appointment_id.to_s,
        namespace: CACHE_NAMESPACE,
        expires_in: DRAFT_CACHE_TTL
      )
    end

    # Look up a previously-cached draft appointment id for +(uuid, referral_number)+.
    # Returns +nil+ on cache miss so callers can fall through to creating a fresh
    # draft via {Eps::AppointmentService#create_draft_appointment}.
    #
    # @param uuid [String] User's UUID
    # @param referral_number [String] CCRA referral identifier
    # @return [String, nil] cached draft id, or +nil+ on miss / blank input
    def fetch_draft_appointment_id(uuid:, referral_number:)
      return nil if uuid.blank? || referral_number.blank?

      Rails.cache.read(generate_draft_key(uuid, referral_number), namespace: CACHE_NAMESPACE)
    end

    # Remove a cached draft id once it has been consumed (successful submit) so
    # that a retry doesn't reuse a Wellhive draft already in +submitted+ state.
    # Safe to call when no entry exists -- +Rails.cache.delete+ is a no-op then.
    #
    # @param uuid [String] User's UUID
    # @param referral_number [String] CCRA referral identifier
    # @return [Boolean] cache deletion result
    def delete_draft_appointment_id(uuid:, referral_number:)
      return false if uuid.blank? || referral_number.blank?

      Rails.cache.delete(generate_draft_key(uuid, referral_number), namespace: CACHE_NAMESPACE)
    end

    private

    # Returns a configured Lockbox instance for encryption/decryption
    #
    # @return [Lockbox] A Lockbox instance with the master key
    def lockbox
      @lockbox ||= begin
        key = Settings.lockbox.master_key&.to_s
        raise ArgumentError, 'Lockbox master key is required' if key.blank?

        Lockbox.new(key:, encode: true)
      end
    end

    # Encrypts data using Lockbox before caching
    #
    # @param data [Hash] The data to encrypt
    # @return [String] The encrypted ciphertext
    def encrypt_data(data)
      lockbox.encrypt(data.to_json)
    end

    # Decrypts data retrieved from cache using Lockbox
    # Returns nil if decryption fails (handles backward compatibility with old unencrypted data)
    #
    # @param encrypted_data [String] The encrypted ciphertext
    # @return [Hash, nil] The decrypted data with symbolized keys, or nil if decryption fails
    def decrypt_data(encrypted_data)
      decrypted_json = lockbox.decrypt(encrypted_data)
      JSON.parse(decrypted_json, symbolize_names: true)
    rescue Lockbox::DecryptionError, JSON::ParserError => e
      Rails.logger.warn(
        "Community Care Appointments: Failed to decrypt cached data (old unencrypted data?): #{e.message}"
      )
      nil
    end

    # Generates a consistent cache key for status check data.
    #
    # @param uuid [String] The user's UUID
    # @param appointment_id [String] The appointment ID
    # @return [String] The generated cache key
    def generate_appointment_data_key(uuid, appointment_id)
      appointment_last4 = appointment_id.to_s.last(4).presence || '0000'
      "#{CACHE_KEY}:#{uuid}:#{appointment_last4}"
    end

    # Generates a consistent cache key for the unified-booking draft id
    # cache. Keyed by full referral number (CCRA referral numbers are short,
    # non-sequential opaque identifiers) plus user uuid so two users sharing
    # a referral can never collide and a single user with multiple referrals
    # gets one cache slot per referral.
    #
    # @param uuid [String] The user's UUID
    # @param referral_number [String] CCRA referral identifier
    # @return [String] The generated cache key
    def generate_draft_key(uuid, referral_number)
      "#{DRAFT_CACHE_KEY}:#{uuid}:#{referral_number}"
    end
  end
end
