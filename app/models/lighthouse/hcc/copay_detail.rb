# frozen_string_literal: true

module Lighthouse
  module HCC
    class CopayDetail
      include Vets::Model
      include MedicalCopays::LighthouseIntegration::DataExtractor

      PAYMENT_DUE_DAYS = 30

      attribute :external_id, String
      attribute :facility, Hash
      attribute :patient, Hash
      attribute :bill_number, String
      attribute :status, String
      attribute :status_description, String
      attribute :invoice_date, String
      attribute :payment_due_date, String
      attribute :account_number, String
      attribute :statement_generated_day, Integer

      attribute :original_amount, Float
      attribute :principal_balance, Float
      attribute :interest_balance, Float
      attribute :administrative_cost_balance, Float
      attribute :principal_paid, Float
      attribute :interest_paid, Float
      attribute :administrative_cost_paid, Float
      attribute :associated_statements, Array
      attribute :associated_invoices, Array

      attribute :line_items, Hash, array: true
      attribute :payments, Hash, array: true

      def initialize(attrs = {})
        @invoice_data = attrs[:invoice_data]
        @account_data = attrs[:account_data]
        @charge_items = attrs[:charge_items] || {}
        @encounters = attrs[:encounters] || {}
        @medication_dispenses = attrs[:medication_dispenses] || {}
        @medications = attrs[:medications] || {}
        @payments_data = attrs[:payments] || []
        @facility_address = attrs[:facility_address]
        @patient_data = attrs[:patient_data]
        @associated_statements_data = attrs[:associated_statements] || []
        assign_attributes
      end

      private

      def assign_attributes
        @external_id = @invoice_data['id']
        @bill_number = extract_bill_number(@invoice_data)
        @status = @invoice_data['status']
        @status_description = @invoice_data.dig('_status', 'valueCodeableConcept', 'text')
        @invoice_date = @invoice_data['date']
        @payment_due_date = calculate_payment_due_date
        @account_number = extract_account_number(@account_data)
        @statement_generated_day = extract_statement_generated_day(@account_data)

        assign_balances
        assign_line_items
        assign_payments
        assign_facility
        assign_patient
        assign_associated_statements
        assign_associated_invoices
      end

      def assign_associated_statements
        @associated_statements = grouped_invoices.values.map(&:first).map do |statement|
          resource = statement['resource']
          time = Time.iso8601(resource['date'])
          facility_num = extract_id_from_reference(resource['issuer']['reference'])
          month = time.month
          year = time.year
          additional_charge_items = statement.dig('resource', '_associated_charge_items') || {}
          total_price_components = @invoice_data['totalPriceComponent'] || []

          {
            'id' => resource['id'],
            'composite_id' => "#{facility_num}-#{month}-#{year}",
            'date' => format_date(resource['date']),
            'bill_number' => extract_bill_number(resource),
            'original_amount' => find_amount(total_price_components, 'Original Amount'),
            'charge_items' => resource['charge_items'] || [],
            'line_items' => sorted_line_items(resource['lineItem'], additional_charge_items:)
          }
        end
      end

      def assign_associated_invoices
        @associated_invoices = sorted_invoices.map do |statement|
          resource = statement['resource']
          facility_num = extract_id_from_reference(resource['issuer']['reference'])
          time = Time.iso8601(resource['date'])
          additional_charge_items = statement.dig('resource', '_associated_charge_items') || {}

          {
            'id' => resource['id'],
            'composite_id' => "#{facility_num}-#{time.month}-#{time.year}",
            'date' => format_date(resource['date']),
            'charge_items' => resource['charge_items'] || [],
            'line_items' => sorted_line_items(resource['lineItem'], additional_charge_items:)
          }
        end
      end

      def grouped_invoices
        sorted_invoices.group_by do |statement|
          date = statement.dig('resource', 'date')
          time = Time.iso8601(date)
          [time.year, time.month]
        end
      end

      def sorted_invoices
        data = @associated_statements_data.presence || []

        return data if data.blank?

        invoice_time = Time.iso8601(@invoice_data['date'])

        filtered = data.filter_map do |statement|
          date_str = statement.dig('resource', 'date')
          next if date_str.blank?

          time = Time.iso8601(date_str)
          [statement, time] if time < invoice_time
        end

        filtered
          .sort_by { |_, time| time }
          .reverse
          .map(&:first)
      end

      def sorted_line_items(line_items, additional_charge_items: {})
        line_item_builder.sorted_line_items(line_items, additional_charge_items:)
      end

      def assign_balances
        total_price_components = @invoice_data['totalPriceComponent'] || []

        @original_amount = find_amount(total_price_components, 'Original Amount')
        @principal_balance = find_amount(total_price_components, 'Principal Balance')
        @interest_balance = find_amount(total_price_components, 'Interest Balance')
        @administrative_cost_balance = find_amount(total_price_components, 'Administrative Cost Balance')
        @principal_paid = find_amount(total_price_components, 'Principal Paid')
        @interest_paid = find_amount(total_price_components, 'Interest Paid')
        @administrative_cost_paid = find_amount(total_price_components, 'Administrative Cost Paid')
      end

      def assign_line_items
        @line_items = sorted_line_items(@invoice_data['lineItem'])
      end

      def assign_facility
        @facility = {
          'name' => @invoice_data.dig('issuer', 'display'),
          'address' => build_facility_address
        }
      end

      def build_facility_address
        return nil unless @facility_address

        {
          'address_line1' => @facility_address[:address_line1],
          'address_line2' => @facility_address[:address_line2],
          'address_line3' => @facility_address[:address_line3],
          'city' => @facility_address[:city],
          'state' => @facility_address[:state],
          'postalCode' => @facility_address[:postalCode]
        }
      end

      def assign_patient
        @patient = build_patient_info
      end

      def build_patient_info
        return nil unless @patient_data

        patient_resource = @patient_data.dig('entry', 0, 'resource')
        return nil unless patient_resource

        address = patient_resource.dig('address', 0) || {}
        name = patient_resource.dig('name', 0) || {}
        given_names = name['given'] || []

        {
          'first_name' => given_names[0],
          'middle_name' => given_names[1],
          'last_name' => name['family'],
          'address' => {
            'address_line1' => address.dig('line', 0),
            'address_line2' => address.dig('line', 1),
            'address_line3' => address.dig('line', 2),
            'city' => address['city'],
            'state' => address['state'],
            'postalCode' => address['postalCode']
          }
        }
      end

      def line_item_builder
        @line_item_builder ||= LineItemBuilder.new(
          charge_items: @charge_items,
          encounters: @encounters,
          medication_dispenses: @medication_dispenses,
          medications: @medications
        )
      end

      def assign_payments
        @payments = @payments_data.map { |p| build_payment(p) }
      end

      def build_payment(payment_data)
        {
          payment_id: payment_data['id'],
          payment_date: payment_data['paymentDate'],
          payment_amount: payment_data.dig('paymentAmount', 'value')&.to_f,
          transaction_number: extract_transaction_number(payment_data),
          bill_number: extract_payment_bill_number(payment_data),
          invoice_reference: extract_invoice_reference(payment_data),
          disposition: payment_data['disposition'],
          detail: build_payment_detail(payment_data)
        }
      end

      def extract_transaction_number(payment_data)
        identifiers = payment_data['identifier'] || []
        identifiers.find { |i| i.dig('type', 'text') == 'Transaction Number' }&.dig('value')
      end

      def extract_bill_number(invoice)
        identifiers = invoice&.dig('identifier') || []
        bill_number = identifiers.find { |i| i.dig('type', 'text') == 'Bill Number' }&.dig('value')
        Rails.logger.warn('Bill number not found in invoice/statement data') if bill_number.blank?
        bill_number
      end

      def extract_payment_bill_number(payment)
        extensions = payment&.dig('extension') || []
        bill_number = extensions.find do |i|
          i.dig('valueIdentifier', 'type', 'text') == 'Bill Number'
        end&.dig('valueIdentifier', 'value')
        Rails.logger.warn('Bill number not found in payment data') if bill_number.blank?
        bill_number
      end

      def extract_account_number(account)
        identifiers = account&.dig('identifier') || []
        account_number = identifiers.find { |i| i.dig('type', 'text') == 'Account number' }&.dig('value')
        Rails.logger.warn('Account number not found in account data') if account_number.blank?
        account_number
      end

      def extract_invoice_reference(payment_data)
        extensions = payment_data['extension'] || []
        target_ext = extensions.find { |e| e['url']&.include?('allocation.target') }
        return nil unless target_ext

        extract_id_from_reference(target_ext.dig('valueReference', 'reference'))
      end

      def build_payment_detail(payment_data)
        details = payment_data['detail'] || []
        details.map do |d|
          {
            type: d.dig('type', 'text'),
            amount: d.dig('amount', 'value')&.to_f
          }
        end
      end

      def find_amount(components, code_text)
        components.find { |c| c.dig('code', 'text') == code_text }&.dig('amount', 'value')&.to_f
      end

      def calculate_payment_due_date
        return nil unless @invoice_date

        (Date.parse(@invoice_date) + PAYMENT_DUE_DAYS.days).iso8601
      rescue Date::Error
        nil
      end

      def extract_id_from_reference(reference)
        return nil unless reference

        reference.split('/').last
      end

      def format_date(time_stamp_string)
        Date.parse(time_stamp_string).strftime('%B %-d, %Y')
      end
    end
  end
end
