# frozen_string_literal: true

require 'cgi'
require 'digest'
require 'openssl'
require 'resolv'
require 'uri'

# lib/ is on $LOAD_PATH but is NOT a Zeitwerk autoload root, so reopening `module Idp` below
# would otherwise create an empty namespace. This file uses Idp::SCAN_STATUSES and raises
# Idp::Error, so it must load the namespace itself rather than relying on load order.
require 'idp'

module Idp
  class Client
    DEFAULT_TIMEOUT = 15
    CONNECT_RESOLVE_RETRY_SECONDS = 30
    ERROR_DETAIL_LOG_LIMIT = 500
    SERVICE_NAME = 'IDP'
    STATSD_KEY = 'api.cave.idp_client'
    HMAC_HEADER_USER_ID = 'X-IDP-User-Id'
    HMAC_HEADER_TIMESTAMP = 'X-IDP-Timestamp'
    HMAC_HEADER_KEY_ID = 'X-IDP-Key-Id'
    HMAC_HEADER_SIGNATURE = 'X-IDP-Signature'

    # Intentionally not a Common::Client::Configuration subclass: VPCE routing and HMAC
    # signing do not fit that base. New HTTP clients should still use Configuration.
    def self.breakers_service
      Breakers::Service.new(
        name: SERVICE_NAME,
        request_matcher: proc do |breakers_service, _request_env, request_service_name|
          request_service_name == breakers_service.name
        end
      )
    end

    def initialize(base_url: nil, connect_url: nil, timeout: nil, hmac_key_id: nil, hmac_secret: nil)
      @base_url = base_url.presence ||
                  Settings.dig(:cave, :idp, :base_url).presence
      @connect_url = connect_url.presence ||
                     Settings.dig(:cave, :idp, :connect_url).presence

      @timeout = resolved_timeout(timeout || Settings.dig(:cave, :idp, :timeout))
      @hmac_key_id = hmac_key_id.presence ||
                     Settings.dig(:cave, :idp, :hmac, :key_id) ||
                     ENV.fetch('bio__IDP_HMAC_KEY_ID', nil)
      @hmac_secret = hmac_secret.presence ||
                     Settings.dig(:cave, :idp, :hmac, :secret) ||
                     ENV.fetch('bio__IDP_HMAC_SECRET', nil)
      raise Idp::Error, 'IDP base URL is not configured' if @base_url.blank?
    end

    def intake(file_name:, pdf_base64:, user_id:)
      post(
        'intake',
        { pdf_b64: pdf_base64 },
        request_context: { operation: 'intake', user_id: },
        headers: { 'X-Filename' => file_name }
      )
    end

    def status(id, user_id:)
      get('status', { id: }, operation: 'status', user_id:)
    end

    def output(id, type:, user_id:)
      get('output', { id:, type: }, operation: 'output', user_id:)
    end

    def download(id, kvpid:, user_id:)
      get('download', { id:, kvpid: }, operation: 'download', user_id:)
    end

    def update(id, kvpid:, payload:, user_id:)
      post(
        'update',
        payload,
        request_context: { operation: 'update', user_id: },
        params: { id:, kvpid: }
      )
    end

    # Forwards a user-correction change set to CAVE for accuracy metrics. The PDFs are not
    # sent — only the per-field { field, label, ocr_value, user_value } records.
    def corrections(id, kvpid:, payload:, user_id:)
      post(
        'corrections',
        payload,
        request_context: { operation: 'corrections', user_id: },
        params: { id:, kvpid: }
      )
    end

    private

    attr_reader :base_url, :connect_url, :timeout, :hmac_key_id, :hmac_secret

    def connection
      @connection ||= Faraday.new(url: normalized_base_url) do |conn|
        conn.use(:breakers, service_name: SERVICE_NAME)
        conn.request :json
        conn.response :json, content_type: /\bjson$/
        conn.response :raise_error
        conn.options.timeout = timeout
        conn.options.open_timeout = timeout
        # Preserve the logical request URL for TLS/SNI while routing the TCP
        # connection to the VPCE-resolved address when connect_url is present.
        conn.adapter :net_http do |http|
          apply_connect_override(http)
        end
      end
    end

    def normalized_base_url
      base_url.end_with?('/') ? base_url : "#{base_url}/"
    end

    def resolved_timeout(timeout_value)
      timeout_integer = Integer(timeout_value, exception: false)
      return timeout_integer if timeout_integer&.positive?

      DEFAULT_TIMEOUT
    end

    def get(path, params = {}, operation:, user_id:)
      request_context = {
        method: 'GET',
        operation:,
        params:,
        body: nil,
        user_id:
      }

      perform_request(operation:) do
        connection.get(path, params) do |req|
          add_identity_headers(req:, request_context:)
        end
      end
    end

    def post(path, body, request_context:, headers: {}, params: {})
      canonical_body = canonical_json(body)
      canonical_params = params.to_h
      signed_request_context = request_context.merge(
        method: 'POST',
        params: canonical_params,
        body: canonical_body
      )

      perform_request(operation: request_context[:operation]) do
        connection.post(path) do |req|
          req.params.update(canonical_params) if canonical_params.present?
          req.headers['Content-Type'] = 'application/json'
          headers.each do |key, value|
            req.headers[key] = value if value.present?
          end
          req.body = canonical_body
          add_identity_headers(req:, request_context: signed_request_context)
        end
      end
    end

    def apply_connect_override(http)
      return if connect_url.blank?

      http.ipaddr = connect_ipaddr if http.respond_to?(:ipaddr=)
    end

    def add_identity_headers(req:, request_context:)
      resolved_user_id = request_context[:user_id].to_s
      raise Idp::Error, 'IDP user identity is required' if resolved_user_id.blank?

      headers = req.headers
      headers[HMAC_HEADER_USER_ID] = resolved_user_id

      return unless signing_configured?

      timestamp = Time.now.to_i.to_s
      headers[HMAC_HEADER_TIMESTAMP] = timestamp
      headers[HMAC_HEADER_KEY_ID] = hmac_key_id if hmac_key_id.present?
      headers[HMAC_HEADER_SIGNATURE] = hmac_signature(
        request_context: request_context.merge(user_id: resolved_user_id),
        timestamp:
      )
    end

    def signing_configured?
      hmac_secret.present?
    end

    def hmac_signature(request_context:, timestamp:)
      payload = [
        timestamp,
        request_context[:method].to_s.upcase,
        request_context[:operation].to_s,
        canonical_query(request_context[:params]),
        Digest::SHA256.hexdigest(request_context[:body].to_s),
        request_context[:user_id].to_s
      ].join("\n")

      OpenSSL::HMAC.hexdigest('SHA256', hmac_secret, payload)
    end

    def canonical_query(params)
      return '' if params.blank?

      pairs = params.to_h.flat_map do |key, value|
        values = value.is_a?(Array) ? value : [value]
        values.compact.map { |entry| [key.to_s, entry.to_s] }
      end

      pairs.sort_by! { |key, value| [key, value] }
      pairs.map { |key, value| "#{CGI.escape(key)}=#{CGI.escape(value)}" }.join('&')
    end

    def canonical_json(value)
      JSON.generate(sort_json(value))
    end

    def sort_json(value)
      case value
      when Hash
        value.keys.sort_by(&:to_s).each_with_object({}) do |key, sorted|
          sorted[key.to_s] = sort_json(value[key])
        end
      when Array
        value.map { |entry| sort_json(entry) }
      else
        value
      end
    end

    def connect_ipaddr
      return if connect_url.blank?
      return @connect_ipaddr if @connect_ipaddr

      raise Idp::Error, 'IDP connect URL could not be resolved' if connect_resolve_cooldown?

      resolved = resolve_connect_ipaddr
      if resolved
        @connect_ipaddr_failed_at = nil
        @connect_ipaddr = resolved
      else
        @connect_ipaddr_failed_at = Time.current
        raise Idp::Error, 'IDP connect URL could not be resolved'
      end
    end

    def connect_resolve_cooldown?
      @connect_ipaddr_failed_at.present? &&
        @connect_ipaddr_failed_at > CONNECT_RESOLVE_RETRY_SECONDS.seconds.ago
    end

    def resolve_connect_ipaddr
      Resolv.getaddresses(connect_destination_host).find(&:present?)
    rescue SocketError => e
      Rails.logger.warn('[Idp::Client] connect_url resolution failed', {
                          connect_url:,
                          connect_destination_host:,
                          error_class: e.class.name,
                          error_message: e.message
                        })
      nil
    rescue URI::InvalidURIError, Resolv::ResolvError
      nil
    end

    def connect_destination_host
      parsed_connect_url.host.presence || connect_url
    end

    def parsed_connect_url
      @parsed_connect_url ||= URI.parse(connect_url)
    end

    def perform_request(operation:)
      start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      response = yield
      log_request_success(operation:, start:, response:)
      response.body
    rescue Faraday::Error => e
      error_context = build_error_context(e.response)
      raise_idp_error(error: e, operation:, start:, error_context:)
    end

    def extract_error_type(body)
      case body
      when Hash
        body['error_type'] || body.dig('error', 'error_type') || body.dig('errors', 0, 'code')
      end
    rescue TypeError
      nil
    end

    def build_error_context(response)
      body = parse_response_body(response&.[](:body))
      headers = normalize_headers(response&.[](:headers))
      {
        status: response&.[](:status),
        headers:,
        body:,
        request_id: extract_request_id(headers),
        detail: extract_error_detail(body),
        failure_category: response.present? ? 'upstream_response' : 'transport'
      }
    end

    def parse_response_body(body)
      return body if body.is_a?(Hash) || body.is_a?(Array)
      return body unless body.is_a?(String)

      stripped = body.strip
      return nil if stripped.blank?

      JSON.parse(stripped)
    rescue JSON::ParserError
      body
    end

    def normalize_headers(headers)
      return {} unless headers.respond_to?(:to_h)

      headers.to_h.transform_keys do |key|
        key.to_s.downcase
      end
    end

    def extract_request_id(headers)
      headers['x-request-id'] || headers['x-amzn-requestid'] || headers['apigw-requestid']
    end

    def extract_error_detail(body)
      detail = case body
               when Hash
                 body.dig('errors', 0, 'detail') ||
                 body.dig('errors', 0, 'title') ||
                 body['error_message'] ||
                 body['error']
               when String
                 body
               end

      return if detail.blank?

      detail.to_s.first(ERROR_DETAIL_LOG_LIMIT)
    end

    def log_request_success(operation:, start:, response:)
      body = response.body
      scan_status = body.is_a?(Hash) ? body['scan_status'] : nil

      Rails.logger.info('[Idp::Client] request success', {
        operation:,
        duration: request_duration(start),
        status: response.status,
        scan_status:,
        error: (body['error'] if body.is_a?(Hash)),
        warnings: (body['warnings'] if body.is_a?(Hash))
      }.compact)

      # Bound the metric-name segment to a fixed set so a bogus upstream scan_status can't create
      # unbounded StatsD cardinality. The RAW value is still logged above; only the metric name
      # is bucketed.
      outcome = if scan_status.nil?
                  'no_scan_status'
                elsif Idp::SCAN_STATUSES.include?(scan_status)
                  scan_status
                else
                  'unknown_scan_status'
                end
      StatsD.increment("#{STATSD_KEY}.#{operation}.#{outcome}")
    end

    def raise_idp_error(error:, operation:, start:, error_context:)
      error_type = extract_error_type(error_context[:body])
      log_request_error(operation:, start:, error:, error_type:, error_context:)
      StatsD.increment("#{STATSD_KEY}.#{operation}.error",
                       tags: ["failure_category:#{error_context[:failure_category]}"])

      raise Idp::Error.new(
        error.message,
        error_type:,
        operation:,
        upstream_status: error_context[:status],
        upstream_body: error_context[:body],
        upstream_headers: error_context[:headers],
        failure_category: error_context[:failure_category]
      )
    end

    def log_request_error(operation:, start:, error:, error_type:, error_context:)
      Rails.logger.error('[Idp::Client] request error', {
                           operation:,
                           duration: request_duration(start),
                           error_class: error.class.name,
                           error_type:,
                           failure_category: error_context[:failure_category],
                           upstream_status: error_context[:status],
                           upstream_request_id: error_context[:request_id],
                           upstream_error_detail: error_context[:detail]
                         })
    end

    def request_duration(start)
      (Process.clock_gettime(Process::CLOCK_MONOTONIC) - start).round(4)
    end
  end
end
