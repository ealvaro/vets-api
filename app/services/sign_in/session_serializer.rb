# frozen_string_literal: true

module SignIn
  class SessionSerializer
    attr_reader :session_records, :current_session_handle

    def initialize(session_records:, current_session_handle:)
      @session_records = session_records
      @current_session_handle = current_session_handle
    end

    def perform
      serialize_session_records
    end

    private

    def serialize_session_records
      session_records.map do |session_record|
        oauth_session = oauth_sessions[session_record.handle]

        {
          handle: session_record.handle,
          client_id: session_record.client_id,
          device_description: session_record.device_description,
          location: session_record.location,
          created_at: session_record.created_at,
          last_activity_at: session_record.last_activity_at,
          signed_out_at: session_record.signed_out_at,
          expiration: oauth_session&.refresh_expiration,
          status: get_session_status(session_record)
        }
      end
    end

    def get_session_status(session_record)
      if session_record.handle == @current_session_handle
        'current'
      elsif session_record.signed_out_at.present?
        'signed_out'
      else
        'active'
      end
    end

    def oauth_sessions
      @oauth_sessions ||= ::SignIn::OAuthSession.where(handle: @session_records.pluck(:handle)).index_by(&:handle)
    end
  end
end
