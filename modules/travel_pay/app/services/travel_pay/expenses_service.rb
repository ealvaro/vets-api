# frozen_string_literal: true

require 'securerandom'
require 'base64'

module TravelPay
  class ExpensesService
    include ExpenseNormalizer
    include Monitorable

    def initialize(auth_manager)
      @auth_manager = auth_manager
    end

    # Method to add a mileage expense, specifically for SMOC
    # TODO: Integrate into create_expense when ready to handle non-SMOC mileage expenses
    def add_expense(params = {})
      auth_session = @auth_manager.authorize

      # check for required params (that don't have a default set in the client)
      unless params['claim_id'] && params['appt_date']
        raise ArgumentError,
              message: 'You must provide a claim ID and appointment date to add an expense.'
      end
      new_expense_response = client.add_mileage_expense(auth_session, params)

      new_expense_response.body['data']
    end

    # Method to handle expense creation via the API
    def create_expense(params = {})
      auth_session = @auth_manager.authorize

      # Validate required params
      raise ArgumentError, 'You must provide a claim ID to create an expense.' unless params['claim_id']

      monitor.log(:info, "Creating expense of type: #{params['expense_type']}")
      # Build the request body for the API
      request_body = build_expense_request_body(params)
      request_body = heic_converter.convert_if_heic(request_body)

      response = client.add_expense(auth_session, params['expense_type'], request_body)
      response.body['data']
    rescue Faraday::Error => e
      monitor.track_request(:error, "Failed to create expense via API: #{e.message}",
                            'travel_pay.expenses.create.api_error')
      TravelPay::ServiceError.raise_mapped_error(e)
    end

    # Method to retrieve an expense by ID via the API
    def get_expense(expense_type, expense_id)
      auth_session = @auth_manager.authorize

      # Validate required params
      raise ArgumentError, 'You must provide an expense type to get an expense.' if expense_type.blank?
      raise ArgumentError, 'You must provide an expense ID to get an expense.' if expense_id.blank?

      monitor.log(:info, "Getting expense of type: #{expense_type} with ID: #{expense_id}")

      response = client.get_expense(auth_session, expense_type, expense_id)
      expense = response.body['data']

      # Normalize expense type
      normalize_expense(expense)
    rescue Faraday::Error => e
      monitor.track_request(:error, "Failed to get expense via API: #{e.message}",
                            'travel_pay.expenses.get.api_error')
      TravelPay::ServiceError.raise_mapped_error(e)
    end

    # Method to handle expense update via the API
    def update_expense(expense_id, expense_type, params = {})
      raise ArgumentError, 'You must provide an expense ID to create an expense.' if expense_id.blank?
      raise ArgumentError, 'You must provide an expense type to create an expense.' if expense_type.blank?
      raise ArgumentError, 'You must provide at least one field to update an expense.' if params.blank?

      auth_session = @auth_manager.authorize
      monitor.log(:info, "Updating expense of type: #{expense_type}")

      # Build the request body for the API
      request_body = build_expense_request_body(params)
      request_body = heic_converter.convert_if_heic(request_body)

      response = client.update_expense(auth_session, expense_id, expense_type, request_body)
      response.body['data']
    end

    # Method to handle expense deletion via the API
    def delete_expense(expense_id:, expense_type:)
      raise ArgumentError, 'You must provide an expense ID to create an expense.' if expense_id.blank?
      raise ArgumentError, 'You must provide an expense type to create an expense.' if expense_type.blank?

      auth_session = @auth_manager.authorize
      monitor.log(:info, "Deleting expense of type: #{expense_type}")

      response = client.delete_expense(auth_session, expense_id, expense_type)
      response.body['data']
    end

    private

    ##
    # Builds the request body for the expense API call
    # Transforms snake_case params to camelCase for the API
    #
    # @param params [Hash] The expense parameters
    # @return [Hash] The formatted request body
    #
    def build_expense_request_body(params)
      # Map of special cases where the API field name doesn't follow simple camelCase conversion
      special_mappings = {
        'purchase_date' => 'dateIncurred',
        'receipt' => 'expenseReceipt'
      }

      request_body = {}

      params.each do |key, value|
        next if value.nil?

        # Use special mapping if it exists, otherwise convert to camelCase
        key_str = key.to_s
        api_key = special_mappings[key_str] || key_str.camelize(:lower)

        # Transform hashes (like receipt)
        request_body[api_key] = camelize_hash_keys(value)
      end

      request_body
    end

    ##
    # Transforms hash values to camelCase
    # For receipt parameter which is a hash with properties
    #
    # @param value [Object] The value to transform
    # @return [Object] The transformed value
    #
    def camelize_hash_keys(value)
      case value
      when Hash
        value.transform_keys { |k| k.to_s.camelize(:lower) }
      else
        value
      end
    end

    def client
      TravelPay::ExpensesClient.new(@auth_manager.user)
    end

    def heic_converter
      @heic_converter ||= TravelPay::HeicConverter.new(@auth_manager.user)
    end
  end
end
