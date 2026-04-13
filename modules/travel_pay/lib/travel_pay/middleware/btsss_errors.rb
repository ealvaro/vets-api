# frozen_string_literal: true

module TravelPay
  module Middleware
    ##
    # Faraday response middleware that normalizes BTSSS error response bodies
    # to the format expected by Common::Client::Middleware::Response::RaiseCustomError.
    #
    # BTSSS returns:
    #   { "statusCode" => 400, "message" => "...", "success" => false, ... }
    #
    # RaiseCustomError expects:
    #   { "detail" => "...", "code" => "...", "source" => "..." }
    #
    class BtsssErrors < Faraday::Middleware
      def on_complete(env)
        return if env.success?

        body = env[:body]
        return unless body.is_a?(Hash)

        body['detail'] = body['message'] if body.key?('message')
        body['code'] = body['statusCode']&.to_s if body.key?('statusCode')
      end
    end
  end
end

Faraday::Response.register_middleware btsss_errors: TravelPay::Middleware::BtsssErrors
