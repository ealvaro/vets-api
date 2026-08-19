# frozen_string_literal: true

require 'securerandom'
require_relative './base_client'
require_relative '../../../lib/travel_pay/constants'

module TravelPay
  class ExpensesClient < TravelPay::BaseClient
    def initialize(user = nil)
      super()
      @user = user
    end

    ##
    # Generic HTTP POST call to the BTSSS 'expenses' endpoints to add a new expense
    # Routes to appropriate endpoint based on expense type
    #
    # @param auth_session [TravelPay::AuthSession] Authentication session with tokens
    # @param expense_type [String] Type of expense (EX: 'other')
    # @param body [Hash] Request body to send to the API
    #
    # @return [Faraday::Response] API response
    #
    def add_expense(auth_session, expense_type, body = {})
      endpoint = expense_endpoint_for_type(expense_type, :add)
      btsss_url = Settings.travel_pay.base_url
      correlation_id = SecureRandom.uuid

      monitor.log(:info, 'Correlation ID', correlation_id:)
      monitor.log(:info, "Adding #{expense_type} expense to endpoint: #{endpoint}")

      log_to_statsd('expense', "add_#{expense_type}") do
        connection(server_url: btsss_url).post(endpoint) do |req|
          req.headers['Authorization'] = "Bearer #{auth_session.veis_token}"
          req.headers['BTSSS-Access-Token'] = auth_session.btsss_token
          req.headers['X-Correlation-ID'] = correlation_id
          req.headers.merge!(claim_headers)
          req.body = body.to_json
        end
      end
    end

    ##
    # Generic HTTP GET call to the BTSSS 'expenses' endpoints to retrieve an expense by ID
    # Routes to appropriate endpoint based on expense type
    #
    # @param auth_session [TravelPay::AuthSession] Authentication session with tokens
    # @param expense_type [String] Type of expense (EX: 'other')
    # @param expense_id [String] UUID of the expense to retrieve
    #
    # @return [Faraday::Response] API response with expense details
    #
    def get_expense(auth_session, expense_type, expense_id)
      btsss_url = Settings.travel_pay.base_url
      correlation_id = SecureRandom.uuid
      endpoint_template = expense_endpoint_for_type(expense_type, :get)
      endpoint = format(endpoint_template, expense_id:)

      monitor.log(:info, 'Correlation ID', correlation_id:)
      monitor.log(:info, "Getting #{expense_type} expense from endpoint: #{endpoint}")

      log_to_statsd('expense', "get_#{expense_type}") do
        connection(server_url: btsss_url).get(endpoint) do |req|
          req.headers['Authorization'] = "Bearer #{auth_session.veis_token}"
          req.headers['BTSSS-Access-Token'] = auth_session.btsss_token
          req.headers['X-Correlation-ID'] = correlation_id
          req.headers.merge!(claim_headers)
        end
      end
    end

    ##
    # HTTP POST call to the BTSSS 'expenses' endpoint to add a new mileage expense
    # API responds with an expenseId
    #
    # @external API params {
    #   "claimId": "string", // uuid of the claim to attach the expense to
    #   "dateIncurred": "2024-10-02T14:36:38.043Z", // This is the appointment date-time
    #   "description": "string", // ?? Not sure what this is or if it is required
    #   "tripType": "string" // Enum: [ OneWay, RoundTrip, Unspecified ]
    # }
    #
    # @params {
    #   'claim_id' => 'string'
    #   'appt_date' => 'string'
    #   'trip_type' => 'OneWay' | 'RoundTrip' | 'Unspecified'
    #   'description' => 'string'
    # }
    #
    # @return expenseId => string
    #
    def add_mileage_expense(auth_session, params = {})
      btsss_url = Settings.travel_pay.base_url
      correlation_id = SecureRandom.uuid
      monitor.log(:info, 'Correlation ID', correlation_id:)
      log_to_statsd('expense', 'add_mileage') do
        connection(server_url: btsss_url).post('api/v2/expenses/mileage') do |req|
          req.headers['Authorization'] = "Bearer #{auth_session.veis_token}"
          req.headers['BTSSS-Access-Token'] = auth_session.btsss_token
          req.headers['X-Correlation-ID'] = correlation_id
          req.headers.merge!(claim_headers)
          trip_type = params['trip_type'] || 'RoundTrip'
          req.body = {
            'claimId' => params['claim_id'],
            'dateIncurred' => params['appt_date'],
            'tripType' => normalize_outbound_trip_type(trip_type),
            'description' => params['description'] || 'mileage'
          }.to_json
        end
      end
    end

    ##
    # Generic HTTP DELETE call to the BTSSS 'expenses' endpoints to delete an expense
    # Routes to appropriate endpoint based on expense type
    #
    # @param auth_session [TravelPay::AuthSession] Authentication session with tokens
    # @param expense_id [String] UUID of the expense
    # @param expense_type [String] Type of expense (EX: 'other')
    # @return [Faraday::Response] API response
    #
    def delete_expense(auth_session, expense_id, expense_type)
      raise ArgumentError, 'Invalid expense_id' unless expense_id&.match?(TravelPay::Constants::UUID_REGEX)

      endpoint_template = expense_endpoint_for_type(expense_type, :delete)
      btsss_url = Settings.travel_pay.base_url
      correlation_id = SecureRandom.uuid
      endpoint = format(endpoint_template, expense_id:)

      monitor.log(:info, 'Correlation ID', correlation_id:)
      monitor.log(:info, "Deleting #{expense_type} expense to endpoint: #{endpoint}")

      log_to_statsd('expense', "delete_#{expense_type}") do
        connection(server_url: btsss_url).delete(endpoint) do |req|
          req.headers['Authorization'] = "Bearer #{auth_session.veis_token}"
          req.headers['BTSSS-Access-Token'] = auth_session.btsss_token
          req.headers['X-Correlation-ID'] = correlation_id
          req.headers.merge!(claim_headers)
        end
      end
    end

    ##
    # Generic HTTP PATCH call to the BTSSS 'expenses' endpoints to update an expense
    # Routes to appropriate endpoint based on expense type
    #
    # @param auth_session [TravelPay::AuthSession] Authentication session with tokens
    # @param expense_id [String] UUID of the expense
    # @param expense_type [String] Type of expense (EX: 'other')
    # @param body [Hash] Request body to send to the API
    # @return [Faraday::Response] API response
    #
    def update_expense(auth_session, expense_id, expense_type, body = {})
      raise ArgumentError, 'Invalid expense_id' unless expense_id&.match?(TravelPay::Constants::UUID_REGEX)

      endpoint_template = expense_endpoint_for_type(expense_type, :patch)
      btsss_url = Settings.travel_pay.base_url
      correlation_id = SecureRandom.uuid
      endpoint = format(endpoint_template, expense_id:)

      monitor.log(:info, 'Correlation ID', correlation_id:)
      monitor.log(:info, "Updating #{expense_type} expense to endpoint: #{endpoint}")

      log_to_statsd('expense', "update_#{expense_type}") do
        connection(server_url: btsss_url).patch(endpoint) do |req|
          req.headers['Authorization'] = "Bearer #{auth_session.veis_token}"
          req.headers['BTSSS-Access-Token'] = auth_session.btsss_token
          req.headers['X-Correlation-ID'] = correlation_id
          req.headers.merge!(claim_headers)
          req.body = body.to_json
        end
      end
    end

    private

    ##
    # Returns the API endpoint for the given expense type and action.
    #
    # Each expense type supports three actions:
    #   - :add    => endpoint for creating a new expense (no expense ID required)
    #   - :get    => endpoint for retrieving a specific expense (requires expense ID)
    #   - :delete => endpoint for deleting a specific expense (requires expense ID)
    #
    # Example usage:
    #  Add a new expense (no ID needed)
    #    endpoint = expense_endpoint_for_type('other', :add)
    #  Get a specific expense by Expense ID
    #    endpoint_template = expense_endpoint_for_type('other', :get)
    #    endpoint = format(endpoint_template, expense_id: '123e4567-e89b-12d3-a456-426614174000')
    #  Delete a specific expense by Expense ID
    #    endpoint_template = expense_endpoint_for_type('mileage', :delete)
    #    endpoint = format(endpoint_template, expense_id: '123e4567-e89b-12d3-a456-426614174000')
    #  Update a specific expense by Expense ID
    #    endpoint_template = expense_endpoint_for_type('mileage', :patch)
    #    endpoint = format(endpoint_template, expense_id: '123e4567-e89b-12d3-a456-426614174000')
    #
    # @param expense_type [String] The type of expense
    # @return [String] The API endpoint path
    #
    def expense_endpoint_for_type(expense_type, action = :add)
      endpoints = TravelPay::Constants::BASE_EXPENSE_PATHS.transform_values do |base|
        { add: base, delete: "#{base}/%<expense_id>s", get: "#{base}/%<expense_id>s", patch: "#{base}/%<expense_id>s" }
      end

      # v4 mileage only supports add (POST) and patch (PATCH); get and delete stay on v2
      if expense_type.to_sym == :mileage
        v4_path = mileage_expense_path
        endpoints[:mileage][:add] = v4_path
        endpoints[:mileage][:patch] = "#{v4_path}/%<expense_id>s"
      end

      endpoint_data = endpoints[expense_type.to_sym]
      raise ArgumentError, "Unsupported expense type: #{expense_type}" unless endpoint_data

      endpoint_data[action]
    end

    def mileage_expense_path
      if Flipper.enabled?(:travel_pay_enable_one_way_mileage, @user)
        # TODO: Move to BASE_EXPENSE_PATHS[:mileage] after migration is complete
        'api/v4/expenses/mileage'
      else
        TravelPay::Constants::BASE_EXPENSE_PATHS[:mileage]
      end
    end

    # TODO: After 8/20/26 TP API release, remove and use spaced values directly.
    def normalize_outbound_trip_type(value)
      return value unless Flipper.enabled?(:travel_pay_api_spaced_keys, @user)

      TravelPay::Constants::TRIP_TYPE_TO_SPACED.fetch(value, value)
    end
  end
end
