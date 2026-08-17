# frozen_string_literal: true

# This client is responsible for interacting with the GCLAWS Accreditation API.
# Supports retrieving accredited entity data (GET) and pushing representative contact updates (POST).

module RepresentationManagement
  module GCLAWS
    class Client
      ALLOWED_TYPES = %w[agents attorneys representatives veteran_service_organizations].freeze
      DEFAULT_PAGE = 1
      DEFAULT_PAGE_SIZE = 1000

      # Shape-appropriate extra fields for standardized error responses, so callers
      # receive the same body shape on failure as on success.
      GET_ERROR_BODY = { 'items' => [], 'totalRecords' => 0 }.freeze
      POST_ERROR_BODY = { 'updated' => 0, 'rejected' => [] }.freeze

      # Maps Faraday exception classes to the log label, HTTP status, and message for each path.
      # Faraday::Error is the catch-all fallback for any error not explicitly mapped.
      GET_ERROR_SPECS = {
        Faraday::UnauthorizedError => { type: 'unauthorized', status: :unauthorized,
                                        message: 'GCLAWS Accreditation unauthorized' },
        Faraday::ConnectionFailed => { type: 'connection_failed', status: :service_unavailable,
                                       message: 'GCLAWS Accreditation unavailable' },
        Faraday::TimeoutError => { type: 'timeout', status: :request_timeout,
                                   message: 'GCLAWS Accreditation request timed out' },
        Faraday::Error => { type: 'error', status: :bad_gateway,
                            message: 'GCLAWS Accreditation request failed' }
      }.freeze

      POST_ERROR_SPECS = {
        Faraday::UnauthorizedError => { type: 'unauthorized', status: :unauthorized,
                                        message: 'GCLAWS RepresentativeContacts unauthorized' },
        Faraday::ConnectionFailed => { type: 'connection_failed', status: :service_unavailable,
                                       message: 'GCLAWS RepresentativeContacts unavailable' },
        Faraday::TimeoutError => { type: 'timeout', status: :request_timeout,
                                   message: 'GCLAWS RepresentativeContacts request timed out' },
        Faraday::Error => { type: 'error', status: :bad_gateway,
                            message: 'GCLAWS RepresentativeContacts request failed' }
      }.freeze

      # Retrieves accredited entities from the GCLAWS API with error handling
      #
      # This method fetches paginated data for different types of accredited entities
      # (agents, attorneys, representatives, veteran service organizations) from the
      # GCLAWS Accreditation API. It includes comprehensive error handling for common
      # API failure scenarios and returns standardized responses.
      #
      # @param type [String] The entity type to retrieve (must be in ALLOWED_TYPES)
      # @param page [Integer] The page number for pagination (default: 1)
      # @param page_size [Integer] The number of records per page (default: 1000)
      # @return [Hash, Faraday::Response] Returns empty hash for invalid types,
      #   successful Faraday response for valid requests, or error response for failures
      #
      # @example Successful request
      #   RepresentationManagement::GCLAWS::Client.get_accredited_entities(type: 'agents')
      #   # => Faraday::Response with body containing agents data
      #
      # @example Invalid entity type
      #   RepresentationManagement::GCLAWS::Client.get_accredited_entities(type: 'invalid')
      #   # => {}
      #
      # @example With pagination
      #   RepresentationManagement::GCLAWS::Client.get_accredited_entities(
      #     type: 'attorneys',
      #     page: 2,
      #     page_size: 50
      #   )
      #
      # Any Faraday error (including auth, connection, timeout, and parse failures from the
      # :json response middleware) is handled internally and returned as a standardized response.
      def self.get_accredited_entities(type:, page: DEFAULT_PAGE, page_size: DEFAULT_PAGE_SIZE)
        return {} unless ALLOWED_TYPES.include?(type)

        GCLAWS::Configuration.new(type:, page:, page_size:).connection.get
      rescue Faraday::Error => e
        respond_to_faraday_error(e, type, GET_ERROR_SPECS, GET_ERROR_BODY)
      end

      # Posts an array of representative contact updates to the GCLAWS RepresentativeContacts endpoint.
      #
      # @param contacts [Array<Hash>] Array of contact hashes matching the RepresentativeContactPostDto schema.
      # @return [Faraday::Response] The API response containing 'updated' count and 'rejected' array.
      #   On error, returns a standardized response whose body includes 'updated' and 'rejected'
      #   so callers see a consistent shape. Callers should still gate on status == 200 before
      #   trusting the values.
      def self.post_representative_contacts(contacts:)
        return build_error_response(:bad_request, 'No contacts provided', POST_ERROR_BODY) if contacts.blank?

        GCLAWS::Configuration.new(type: 'representative_contacts').post_connection.post do |req|
          req.body = contacts
        end
      rescue Faraday::Error => e
        respond_to_faraday_error(e, 'representative_contacts', POST_ERROR_SPECS, POST_ERROR_BODY)
      end

      # Logs and builds a standardized error response for a Faraday error, using the
      # per-path spec table. Falls back to the Faraday::Error spec for unmapped subclasses.
      #
      # @param exception [Faraday::Error] The raised error
      # @param entity_type [String] The entity type being requested
      # @param specs [Hash] The GET or POST error spec table
      # @param body_extra [Hash] Shape-appropriate extra body fields (GET vs POST)
      # @return [Faraday::Response] A standardized error response
      def self.respond_to_faraday_error(exception, entity_type, specs, body_extra)
        spec = specs[exception.class] || specs[Faraday::Error]
        handle_api_error(spec[:type], entity_type, exception)
        build_error_response(spec[:status], spec[:message], body_extra)
      end

      # Handles API errors with logging and Slack notifications for critical issues
      #
      # @param error_type [String] The type of error (unauthorized, connection_failed, timeout)
      # @param entity_type [String] The entity type being requested
      # @param exception [Exception] The original exception
      def self.handle_api_error(error_type, entity_type, exception)
        error_message = "GCLAWS Accreditation API #{error_type} error for #{entity_type}: #{exception.message}"

        # Log to Rails logger
        log_error(error_message)

        # Send Slack notification for critical errors
        notify_slack_api_error(error_type, entity_type, exception)
      end

      # Sends a notification to Slack for critical API errors
      #
      # @param error_type [String] The type of error
      # @param entity_type [String] The entity type being requested
      # @param exception [Exception] The original exception
      def self.notify_slack_api_error(error_type, entity_type, exception)
        message = "🚨 GCLAWS API Error Alert!\n" \
                  "Error Type: #{error_type.humanize}\n" \
                  "Entity Type: #{entity_type}\n" \
                  "Message: #{exception.message}\n" \
                  "Time: #{Time.current}\n" \
                  'Action: Automatic retry may occur, manual review recommended for persistent issues'

        log_to_slack_api_channel(message)
      rescue => e
        # Don't let Slack notification failures break the main flow
        log_error("Failed to send Slack notification: #{e.message}")
      end

      # Sends a notification to the Slack channel for API issues
      #
      # @param message [String] The message to send to Slack
      def self.log_to_slack_api_channel(message)
        return unless Settings.vsp_environment == 'production'

        slack_client = SlackNotify::Client.new(
          webhook_url: Settings.edu.slack.webhook_url,
          channel: '#benefits-representation-management-notifications',
          username: 'RepresentationManagement::GCLAWS::ClientBot'
        )
        slack_client.notify(message)
      end

      # Builds a standardized error response
      #
      # @param status [Symbol] The HTTP status symbol
      # @param error_message [String] The error message
      # @param body_extra [Hash] Shape-appropriate extra body fields (e.g. GET pagination
      #   fields or POST updated/rejected fields) so the error body matches the success shape
      # @return [Faraday::Response] A mock response object
      def self.build_error_response(status, error_message, body_extra = {})
        Faraday::Response.new(
          status:,
          body: { 'errors' => error_message }.merge(body_extra)
        )
      end

      # Logs an error message to the Rails logger
      #
      # @param message [String] The error message to log
      def self.log_error(message)
        Rails.logger.error("RepresentationManagement::GCLAWS::Client error: #{message}")
      end
    end
  end
end
