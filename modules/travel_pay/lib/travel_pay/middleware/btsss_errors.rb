# frozen_string_literal: true

module TravelPay
  module Middleware
    ##
    # Faraday response middleware that normalizes BTSSS error response bodies
    # to the format expected by Common::Client::Middleware::Response::RaiseCustomError.
    #
    # BTSSS returns two common error shapes:
    #
    #   Shape 1 (detail in message):
    #   { "statusCode" => 400, "message" => "Validation failed: ...", "success" => false, "data" => nil }
    #
    #   Shape 2 (detail in data array):
    #   { "statusCode" => 400, "message" => "Bad Request", "success" => false,
    #     "data" => ["Validation Failed: ...", "Validation Failed: ..."] }
    #
    # RaiseCustomError expects:
    #   { "detail" => "...", "code" => "...", "source" => "..." }
    #
    class BtsssErrors < Faraday::Middleware
      def on_complete(env)
        return if env.success?

        body = env[:body]

        # When the response body is not JSON (e.g., gateway-level 502/503 errors
        # that return HTML or plain text), convert it to the Hash structure that
        # RaiseCustomError expects so that `detail` is populated in logs.
        unless body.is_a?(Hash)
          env[:body] = {
            'detail' => body.to_s.truncate(2000),
            'code' => "_#{env.status}"
          }
          return
        end

        body['detail'] = build_detail(body) if body.key?('message')
        body['code'] = "_#{body['statusCode']}" if body.key?('statusCode')
      end

      private

      ##
      # Build the detail string from the BTSSS error response.
      # If `data` contains an array of validation messages, join them with the
      # top-level message for a complete error description.
      #
      def build_detail(body)
        message = body['message']
        data = body['data']

        if data.is_a?(Array) && data.any? { |item| item.is_a?(String) }
          validation_messages = data.select { |item| item.is_a?(String) }
          "#{message}: #{validation_messages.join('; ')}"
        else
          message
        end
      end
    end
  end
end

Faraday::Response.register_middleware btsss_errors: TravelPay::Middleware::BtsssErrors
