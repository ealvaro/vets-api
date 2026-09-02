# frozen_string_literal: true

require 'common/client/configuration/base'

module SearchKendra
  class Configuration < Common::Client::Configuration::Base
    def service_name
      'SearchKendra/Results'
    end

    def index_id
      Settings.search_kendra.index_id
    end

    def region
      Settings.search_kendra.region
    end

    def client
      @client ||= Aws::Kendra::Client.new(region:)
    end

    # Placeholder URI. Kendra uses the AWS SDK, but Base always parses
    # base_path when building breakers metadata.
    def base_path
      "kendra://#{Settings.search_kendra.region}"
    end

    # Required by Base, but never used for AWS requests.
    def breakers_matcher
      proc { false }
    end

    # AWS SDK errors aren't handled by Base's default classifier.
    def breakers_exception_handler
      proc { |exception| exception.is_a?(Aws::Kendra::Errors::ServiceError) }
    end

    def with_breakers
      return yield if Breakers.disabled?

      service = breakers_service
      outage = service.latest_outage

      if outage_blocks_request?(outage, service)
        notify_plugins(:on_skipped_request, service)
        raise Breakers::OutageException.new(outage, service)
      end

      begin
        result = yield
        service.add_success
        outage&.end!
        notify_plugins(:on_success, service)
        result
      rescue => e
        handle_breaker_error(service, outage, e)
        raise
      end
    end

    def relevance_tuning_config
      RELEVANCE_TUNING_CONFIG
    end

    RELEVANCE_TUNING_CONFIG = [
      {
        name: '_source_uri',
        relevance: { importance: 5, value_importance_map: {} }
      },
      {
        name: 'domain',
        relevance: {
          importance: 1,
          value_importance_map: { 'www.va.gov' => 8 }
        }
      },
      {
        name: 'location',
        relevance: {
          importance: 1,
          value_importance_map: { 'NONE' => 8 }
        }
      },
      {
        name: 'path_depth',
        relevance: { importance: 2, rank_order: 'DESCENDING' }
      }
    ].freeze

    private

    def outage_blocks_request?(outage, service)
      return false unless outage
      return false if outage.ended?
      return false if outage.forced?
      return false if outage.ready_for_retest?(wait_seconds: service.seconds_before_retry)

      true
    end

    def handle_breaker_error(service, outage, exception)
      return unless service.exception_represents_server_error?(exception)

      service.add_error
      outage&.update_last_test_time!
      Breakers.client.logger&.warn(
        msg: 'Breakers failed request',
        service: service.name,
        error: "#{exception.class.name} - #{exception.message}"
      )
      notify_plugins(:on_error, service)
    end

    def notify_plugins(hook, service)
      Breakers.client.plugins.each do |plugin|
        next unless plugin.respond_to?(hook)

        if hook == :on_skipped_request
          plugin.public_send(hook, service)
        else
          plugin.public_send(hook, service, nil, nil)
        end
      end
    end
  end
end
