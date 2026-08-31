# frozen_string_literal: true

module AskVAApi
  module Predictions
    module QuestionClassifiers
      class ServiceClient
        DEFAULT_TIMEOUT = 4 # seconds, per technical brief

        MODEL_PATHS = {
          'Category' => '/predictions/category'
        }.freeze

        def initialize
          @url = Settings.ask_va_api.prediction_service.url
        end

        def self.timeout
          configured = Settings.ask_va_api.prediction_service.timeout.to_i
          configured.positive? ? configured : DEFAULT_TIMEOUT
        end

        def predict(model_name:, question:)
          response = http_client.post(
            MODEL_PATHS.fetch(model_name) { raise ArgumentError, "Unknown model_name: #{model_name}" },
            build_request_body(question:, model_name:)
          )

          handle_response(response)
        rescue PredictionServiceError
          raise
        rescue Faraday::TimeoutError => e
          raise_service_error("Prediction Service did not respond within #{self.class.timeout} seconds", 504, e)
        rescue Faraday::ConnectionFailed => e
          raise_service_error('Connection to Prediction Service failed', 502, e)
        rescue Faraday::ClientError => e
          raise_service_error('Client error calling Prediction Service', 400, e)
        rescue Faraday::ServerError => e
          raise_service_error('Prediction Service error', 502, e)
        rescue => e
          raise_service_error('Unexpected error calling Prediction Service', 500, e)
        end

        private

        def http_client
          Faraday.new(
            url: @url,
            headers: default_headers,
            request: { timeout: self.class.timeout }
          ) do |conn|
            conn.response :betamocks if mock_enabled?
            conn.request :json
            conn.response :json
            conn.adapter :net_http
          end
        end

        def mock_enabled?
          Settings.betamocks.enabled && Settings.ask_va_api.use_mocks
        end

        def default_headers
          { 'Content-Type' => 'application/json' }
        end

        def build_request_body(question:, model_name:)
          {
            question:,
            model_name:
          }
        end

        ERROR_MESSAGES = {
          422 => 'Invalid request format or missing required fields',
          401 => 'Unauthorized to access Prediction Service',
          403 => 'Unauthorized to access Prediction Service',
          502 => 'Prediction Service exceeded its own upstream timeout',
          503 => 'Model is not setup properly',
          504 => 'Prediction Service gateway timeout'
        }.freeze

        def handle_response(response)
          return parse_body(response.body) if response.status == 200

          raise PredictionServiceError.new(error_message(response.status), error_status(response.status), response.body)
        end

        # Betamocks can return the cached body as a raw string, bypassing the json response middleware
        def parse_body(body)
          body.is_a?(String) ? JSON.parse(body) : body
        end

        def error_message(status)
          ERROR_MESSAGES.fetch(status) do
            status >= 500 ? 'Prediction Service error' : "Unexpected response status #{status}"
          end
        end

        # Pass through upstream statuses we mirror verbatim; collapse anything else 5xx to 502
        PASSTHROUGH_STATUSES = [502, 503, 504].freeze

        def error_status(status)
          return status if PASSTHROUGH_STATUSES.include?(status) || status < 500

          502
        end

        def raise_service_error(message, status, original_error)
          Rails.logger.error('AskVA Prediction Service Error', { message:, status:, error: original_error.message })
          raise PredictionServiceError.new(message, status, original_error.message)
        end
      end

      class PredictionServiceError < StandardError
        attr_reader :status, :details

        def initialize(message, status = 500, details = nil)
          super(message)
          @status = status
          @details = details
        end
      end
    end
  end
end
