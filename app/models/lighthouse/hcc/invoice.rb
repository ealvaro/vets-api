# frozen_string_literal: true

module Lighthouse
  module HCC
    class Invoice
      include Vets::Model
      include MedicalCopays::LighthouseIntegration::DataExtractor

      CHARGED_COMPONENT_TYPES = %w[base surcharge].freeze

      # Takes [type, amount] pairs so raw FHIR components and already-flattened
      # line item components share one rule.
      def self.sum_charged_amounts(typed_amounts)
        (typed_amounts || []).sum do |type, amount|
          CHARGED_COMPONENT_TYPES.include?(type) ? amount.to_f : 0.0
        end
      end

      attribute :external_id, String
      attribute :facility, String
      attribute :facility_id, String
      attribute :city, String
      attribute :latest_billing_ref, String
      attribute :current_balance, Float
      attribute :previous_balance, String
      attribute :previous_unpaid_balance, String
      attribute :last_updated_at, String
      attribute :invoice_date, String
      attribute :last_credit_debit, Float
      attribute :url, String
      attribute :line_items, Hash, array: true
      attribute :statement_generated_day, Integer

      def initialize(params)
        @params = params
        assign_attributes
      end

      def assign_attributes
        line_item = @params.dig('resource', 'lineItem')&.first
        @latest_billing_ref = line_item
                              &.dig('chargeItemReference', 'reference')
                              &.split('/')
                              &.last
        @last_credit_debit = line_item&.dig('priceComponent', 0, 'amount', 'value')

        @last_updated_at = @params.dig('resource', 'meta', 'lastUpdated')

        @current_balance = calculate_current_balance ? calculate_current_balance.compact.sum : 0.0
        @previous_balance = get_previous_balance
        @previous_unpaid_balance = get_previous_unpaid_balance

        @url = @params.dig('resource', 'fullUrl')
        @external_id = @params.dig('resource', 'id')
        @invoice_date = @params.dig('resource', 'date')

        @line_items = @params.dig('resource', 'line_items') || []
        assign_facility_attr
        assign_account_attr
      end

      def assign_account_attr
        account_data = @params.dig('resource', 'account')
        @statement_generated_day = extract_statement_generated_day(account_data)
      end

      def assign_facility_attr
        @facility = @params.dig('resource', 'issuer', 'display')
        @facility_id = @params.dig('resource', 'facility_id')
        @city = @params.dig('resource', 'city')
      end

      private

      def calculate_current_balance
        @params.dig('resource', 'totalPriceComponent')&.map do |tpc|
          next if tpc['type'] == 'informational'

          tpc['amount']['value']
        end
      end

      def get_previous_balance
        @params['resource']['totalPriceComponent'].find do |c|
          c['type'] == 'informational' && c.dig('code', 'text') == 'Original Amount'
        end&.dig('amount', 'value')&.to_f
      end

      def get_previous_unpaid_balance
        typed_amounts = @params['resource']['totalPriceComponent'].map do |component|
          [component['type'], component.dig('amount', 'value')]
        end

        self.class.sum_charged_amounts(typed_amounts)
      end
    end
  end
end
