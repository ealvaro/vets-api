# frozen_string_literal: true

module Idp
  # Canonical CAVE scan_status values (the shared failure contract). Single source of truth
  # referenced by both Idp::Client (StatsD metric bucketing) and V0::CaveController (envelope
  # validation) so the two can't drift. Also bounds metric-name cardinality: only these values
  # (plus explicit 'no_scan_status' / 'unknown_scan_status' buckets) ever appear in a metric name.
  SCAN_STATUSES = %w[pending completed completed_with_errors failed].freeze

  class Error < StandardError
    attr_reader :error_type, :operation, :upstream_status, :upstream_body, :upstream_headers, :failure_category

    def initialize(message = nil, error_type: nil, operation: nil, **context)
      super(message)
      context.assert_valid_keys(
        :upstream_status,
        :upstream_body,
        :upstream_headers,
        :failure_category
      )
      @error_type = error_type
      @operation = operation
      @upstream_status = context[:upstream_status]
      @upstream_body = context[:upstream_body]
      @upstream_headers = context[:upstream_headers]
      @failure_category = context[:failure_category]
    end

    def upstream_status_code
      Integer(upstream_status, exception: false)
    end

    def upstream_response?
      upstream_status_code.present?
    end

    def transport_failure?
      failure_category.to_s == 'transport' || !upstream_response?
    end
  end

  # Returns the appropriate IDP client for the current environment.
  #
  # - Production/staging: Idp::Client (real HTTP calls)
  # - Non-production: controlled by cave.idp.mock (defaults to true in dev/test)
  #
  # Developers who need the real service locally can set IDP_USE_LIVE=true.
  def self.client
    if use_live_client?
      # Lazy-required (rather than at the top of this file) because idp/client.rb requires this
      # file back for the namespace, and a top-level require here would be circular.
      require 'idp/client' unless defined?(Client)
      Client.new
    else
      require 'idp/mock_client' unless defined?(MockClient)
      MockClient.new
    end
  end

  def self.use_live_client?
    return true if Rails.env.production?

    # use ENV['IDP_USE_LIVE'] if you need to develop against the live client on localhost
    return true if ENV['IDP_USE_LIVE'].present?

    mock_setting = Settings.dig(:cave, :idp, :mock)
    return !mock_setting unless mock_setting.nil?

    false
  end
  private_class_method :use_live_client?
end
