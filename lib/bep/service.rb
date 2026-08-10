# frozen_string_literal: true

require 'bep/configuration'
require 'bep/monitor'
require 'common/client/base'

module BEP
  class Service < Common::Client::Base
    def perform_with_monitoring(options = {})
      method = options[:method]
      path = options[:path]

      # endpoint_name is used to tag this request as being part of a particular endpoint or group of endpoints
      # ideally this would be provided by the caller, but in the case it's not we'll try to infer it from
      # the path itself
      endpoint_name = options[:endpoint_name] || path.split('/').reject(&:empty?).first || 'default'

      monitor.track_api_request(method, endpoint_name, additional_context: options[:logging_context] || {},
                                                       call_location: caller_locations.first) do
        perform(method, path, options[:params], options[:headers], options[:request_options])
      end
    end

    protected

    def monitor
      @monitor ||= Monitor.new('bep-generic-api')
    end
  end
end
