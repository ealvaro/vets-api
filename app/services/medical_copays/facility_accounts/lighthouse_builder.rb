# frozen_string_literal: true

module MedicalCopays
  module FacilityAccounts
    class LighthouseBuilder
      FACILITY_IDENTIFIER_SYSTEM = 'https://api.va.gov/services/fhir/v0/r4/NamingSystem/va-facility-identifier'
      STATION_PREFIX = 'vha_'
      ORG_CACHE_STATSD_KEY = 'api.mcp.facility_accounts.org_cache'

      def initialize(lighthouse_service:)
        @lighthouse_service = lighthouse_service
      end

      def build_facility_accounts(status: nil)
        invoices = @lighthouse_service.list_months(status:).entries
        grouped = invoices.group_by { |invoice| get_station_id(invoice.facility_id) }
        log_unresolved(grouped.delete(nil))
        grouped.map { |station_id, station_invoices| account_for_station(station_id, station_invoices) }
      end

      def build_facility_account(station_id)
        invoices = invoices_for_station(station_id)
        return nil if invoices.blank?

        account_for_station(station_id, invoices, include_details: true)
      end

      private

      def invoices_for_station(station_id)
        @lighthouse_service.list_months.entries.select do |invoice|
          get_station_id(invoice.facility_id) == station_id
        end
      end

      def account_for_station(station_id, invoices, include_details: false)
        statement_date = statement_date_for(invoices.first)

        attributes = {
          station_id:,
          facility_name: invoices.first.facility,
          is_cerner: false,
          current_balance: FacilityAccount.sum_balances(invoices),
          past_due_balance: FacilityAccount.sum_balances(invoices.select { |invoice| past_due?(invoice) }),
          statement_date:,
          due_date: statement_date + FacilityAccount::PAYMENT_DUE_DAYS
        }
        attributes.merge!(detail_attributes(invoices)) if include_details

        FacilityAccount.new(attributes)
      end

      def detail_attributes(invoices)
        details = invoices.map do |invoice|
          @lighthouse_service.get_detail(id: invoice.external_id, include_associated: false)
        end

        {
          account_number: details.first&.account_number,
          transactions: build_transactions(details)
        }
      end

      def build_transactions(details)
        details
          .flat_map { |detail| charge_transactions(detail) + payment_transactions(detail) }
          .sort_by { |transaction| transaction[:date].to_s }
          .reverse
      end

      def charge_transactions(detail)
        log_missing_charge_items(detail.line_items)

        detail.line_items.map do |line_item|
          charge_item_id = line_item[:billing_reference]
          charged_amounts = (line_item[:price_components] || []).map do |component|
            [component[:type], component[:amount]]
          end

          {
            id: charge_item_id,
            type: 'charge',
            date: transaction_date(line_item[:date_posted]),
            description: line_item[:description],
            amount: Lighthouse::HCC::Invoice.sum_charged_amounts(charged_amounts),
            billing_reference: detail.bill_number,
            provider: line_item[:provider_name],
            medication: line_item[:medication]
          }
        end
      end

      def payment_transactions(detail)
        detail.payments.map do |payment|
          {
            id: payment[:payment_id],
            type: 'payment',
            date: transaction_date(payment[:payment_date]),
            amount: payment[:payment_amount]&.abs
          }
        end
      end

      def transaction_date(posted)
        Date.parse(posted).iso8601 if posted.present?
      rescue Date::Error
        nil
      end

      def log_missing_charge_items(line_items)
        missing = line_items.select { |line_item| line_item[:description].blank? }
        return if missing.blank?

        charge_item_ids = missing.filter_map { |line_item| line_item[:billing_reference] }.uniq.join(', ')
        Rails.logger.warn("FacilityAccounts::LighthouseBuilder no charge item for: #{charge_item_ids}, " \
                          "#{missing.size} unlabeled transaction(s)")
      end

      def log_unresolved(invoices)
        return if invoices.blank?

        org_ids = invoices.map(&:facility_id).uniq.join(', ')
        Rails.logger.warn("FacilityAccounts::LighthouseBuilder no station id for orgs: #{org_ids}, " \
                          "excluding #{invoices.size} invoice(s)")
      end

      def past_due?(invoice)
        statement_date_for(invoice) + FacilityAccount::PAYMENT_DUE_DAYS < Time.zone.today
      end

      def statement_date_for(invoice)
        invoice_date = Date.parse(invoice.invoice_date)
        # HCCC guarantees account-statementGeneratedDay, but local mock accounts are missing it.
        # Remove this fallback once vets-api-mockdata carries the extension everywhere.
        return invoice_date if invoice.statement_generated_day.blank?

        Date.new(invoice_date.year, invoice_date.month, invoice.statement_generated_day)
      end

      def organization(org_id)
        @organizations ||= {}
        return @organizations[org_id] if @organizations.key?(org_id)

        @organizations[org_id] = @lighthouse_service.fetch_organization(org_id, ORG_CACHE_STATSD_KEY)
      end

      def get_station_id(org_id)
        identifiers = organization(org_id)&.dig('identifier') || []
        facility_identifier = identifiers.find { |identifier| identifier['system'] == FACILITY_IDENTIFIER_SYSTEM }
        facility_identifier&.dig('value')&.delete_prefix(STATION_PREFIX)&.slice(FacilityAccount::STATION_ID_PATTERN)
      end
    end
  end
end
