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

      def build_facility_accounts
        invoices = @lighthouse_service.list_months.entries
        grouped = invoices.group_by { |invoice| get_station_id(invoice.facility_id) }
        log_unresolved(grouped.delete(nil))
        grouped.map do |station_id, station_invoices|
          statement_date = statement_date_for(station_invoices.first)
          FacilityAccount.new(
            station_id:,
            facility_name: station_invoices.first.facility,
            is_cerner: false,
            current_balance: FacilityAccount.sum_balances(station_invoices),
            past_due_balance: FacilityAccount.sum_balances(station_invoices.select { |invoice| past_due?(invoice) }),
            statement_date:,
            due_date: statement_date + FacilityAccount::PAYMENT_DUE_DAYS
          )
        end
      end

      def build_facility_account(station_id, include_transactions: true)
        # TODO: detail fan-out for the org(s) resolving to station_id
      end

      private

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
