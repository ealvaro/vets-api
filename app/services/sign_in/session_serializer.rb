# frozen_string_literal: true

module SignIn
  class SessionSerializer
    attr_reader :sessions, :current_session_handle

    def initialize(sessions:, current_session_handle:)
      @sessions = sessions
      @current_session_handle = current_session_handle
    end

    def perform
      serialize_sessions
    end

    private

    def serialize_sessions
      client_ids = @sessions.map(&:client_id).uniq
      clients = ::SignIn::ClientConfig.where(client_id: client_ids).index_by(&:client_id)

      @sessions.map do |session|
        client = clients[session.client_id]

        {
          handle: session.handle,
          session_type: client&.authentication,
          client_id: session.client_id,
          expiration: session.refresh_expiration,
          current: session.handle == @current_session_handle
        }
      end
    end
  end
end
