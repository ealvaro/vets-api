# frozen_string_literal: true

module Crm
  class Service
    attr_reader :icn, :logger, :token

    def self.crm_env
      env = {
        'localhost' => 'betamocks',
        'test' => 'iris-dev',
        'development' => 'ava-int',
        'staging' => 'ava-qa',
        'production' => 'veft'
      }

      env['production'] = 'ava' if Flipper.enabled?(:ask_va_api_patsr_separation)
      env['staging'] = 'ava-int' if Flipper.enabled?(:ask_va_api_ava_int_for_staging)
      # DTC controls preprod now, but we are doubtful that they are testing through va.gov,
      # leaving this in so that it can be brought back quickly if needed, but should reevaluate
      # if we still need this long term
      env['staging'] = 'ava-preprod' if Flipper.enabled?(:ask_va_api_preprod_for_end_to_end_testing)

      env
    end

    def initialize(icn:, logger: LogService.new)
      @icn = icn
      @token = CrmToken.new.call
      @logger = logger
    end

    # Calls the CRM API with given method, endpoint, and optional payload
    def call(endpoint:, method: :get, payload: {})
      response = connection.request(method:, endpoint:, payload:, organization:)

      parse_response(response.body)
    rescue => e
      log_error(endpoint, @connection&.service_name || 'VEIS-API')

      Faraday::Response.new(
        response_body: extract_body_from(e),
        status: extract_status_from(e)
      )
    end

    private

    def connection
      @connection ||= Crm::Connection.new(icn:, token:)
    end

    def organization
      env = Settings.vsp_environment.to_s.downcase
      @organization ||= self.class.crm_env.fetch(env, 'iris-dev')
    end

    def parse_response(body)
      JSON.parse(body, symbolize_names: true)
    end

    def extract_body_from(error)
      return error.original_body if error.respond_to?(:original_body)

      if error.respond_to?(:response) && error.response.is_a?(Hash)
        error.response[:body] || error.message
      else
        { error: error.message }
      end
    end

    def extract_status_from(error)
      return error.original_status if error.respond_to?(:original_status)

      if error.respond_to?(:response) && error.response.is_a?(Hash)
        error.response[:status] || 500
      else
        500
      end
    end

    def log_error(endpoint, error_type)
      logger.call('api_call.error', tags: {
                    endpoint:,
                    error: error_type
                  })
    end
  end
end
