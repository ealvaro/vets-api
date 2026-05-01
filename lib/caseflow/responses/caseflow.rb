# frozen_string_literal: true

require 'vets/model'
require 'logging/monitor'

module Caseflow
  module Responses
    ##
    # Model for a caseflow' responses. Body is passed straight through from caseflow
    # with a validation check that it matches the expected schema.
    #
    # @param body [String] The original body from the service.
    # @param status [Integer] The HTTP status code from the service.
    #
    # @!attribute body
    #   @return [Integer] Validated response body.
    # @!attribute status
    #   @return [Integer] The HTTP status code.
    #
    class Caseflow
      include Vets::Model

      STATSD_KEY_PREFIX = 'api.appeals'

      attribute :body, String
      attribute :status, Integer

      def initialize(body, status)
        @body = body if json_format_is_valid?(body)
        @status = status
        super()
      end

      private

      def json_format_is_valid?(body)
        schema_path = Rails.root.join('lib', 'caseflow', 'schema', 'appeals.json').to_s
        errors = JSON::Validator.fully_validate(schema_path, body, strict: false)
        if errors.any?
          monitor.track_request(
            :warn,
            'Caseflow appeals response failed schema validation',
            "#{STATSD_KEY_PREFIX}.schema_validation_failure",
            call_location: caller_locations(1, 1)[0],
            validation_errors: errors
          )
        end
        true
      end

      def monitor
        @monitor ||= ::Logging::Monitor.new('appeals')
      end
    end
  end
end
