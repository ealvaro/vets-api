# frozen_string_literal: true

module MedicalCopays
  module LighthouseIntegration
    module InvoiceEntryChargeItemHelper
      private

      def add_line_items_to_invoices!(entries)
        invoices_charge_items = fetch_invoices_charge_items(entries)

        entries.each do |entry|
          invoice_id = entry.dig('resource', 'id')
          resource = entry['resource'] || {}
          charge_items = invoices_charge_items[invoice_id] || {}
          resource['charge_items'] = charge_items
          resource['line_items'] = merge_bill_number(
            copay_line_items_for_invoice(resource['lineItem'], charge_items),
            resource
          )
          entry['resource'] = resource
        end

        entries
      end

      def merge_bill_number(line_items, resource)
        bill_number = extract_bill_number(resource)
        return line_items if bill_number.blank?

        line_items.map { |li| li.merge(bill_number:) }
      end

      def extract_bill_number(resource)
        identifiers = resource['identifier'] || []
        identifiers.find { |i| i.dig('type', 'text') == 'Bill Number' }&.dig('value')
      end

      def copay_line_items_for_invoice(fhir_line_items, additional_charge_items)
        Lighthouse::HCC::LineItemBuilder.new(
          charge_items: {},
          encounters: {},
          medication_dispenses: {},
          medications: {}
        ).sorted_line_items(fhir_line_items, additional_charge_items:)
      end

      def map_invoice_to_charge_item(entries)
        entries.each_with_object({}) do |entry, invoice_to_charge_item_ids|
          invoice_id = entry.dig('resource', 'id')
          next if invoice_id.blank?

          resource = entry['resource'] || {}
          charge_item_ids = extract_charge_item_ids(resource)
          invoice_to_charge_item_ids[invoice_id] = charge_item_ids
        end
      end

      def fetch_invoices_charge_items(entries)
        invoice_to_charge_item_ids = map_invoice_to_charge_item(entries)
        return {} if invoice_to_charge_item_ids.empty?

        futures = invoice_to_charge_item_ids.filter_map do |invoice_id, charge_item_ids|
          next if charge_item_ids.blank?

          Concurrent::Promises.future do
            [invoice_id, PaginatedService::ChargeItemService.new(@icn).fetch_paginated_charge_items(charge_item_ids)]
          end
        end

        futures.each_with_object({}) do |future, hash|
          invoice_id, items_by_id = future.value!
          hash[invoice_id] = items_by_id
        end
      end
    end
  end
end
