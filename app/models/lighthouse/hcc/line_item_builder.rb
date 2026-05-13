# frozen_string_literal: true

module Lighthouse
  module HCC
    class LineItemBuilder
      def initialize(charge_items: {}, encounters: {}, medication_dispenses: {}, medications: {})
        @charge_items = charge_items
        @encounters = encounters
        @medication_dispenses = medication_dispenses
        @medications = medications
      end

      def sorted_line_items(line_items, additional_charge_items: {})
        return [] if line_items.blank?

        line_items
          .map { |li| build_line_item(li, additional_charge_items:) }
          .partition { |li| li[:date_posted].present? }
          .then do |with_date, without_date|
            with_date.sort_by { |li| li[:date_posted] }.reverse + without_date
          end
      end

      private

      def build_line_item(invoice_line_item, additional_charge_items: {})
        charge_items = @charge_items.merge(additional_charge_items)
        charge_item_id = extract_id_from_reference(invoice_line_item.dig('chargeItemReference', 'reference'))
        charge_item = charge_items[charge_item_id] || {}

        {
          billing_reference: charge_item_id,
          date_posted: extract_date_posted(charge_item),
          description: charge_item.dig('code', 'text'),
          provider_name: extract_provider_name(charge_item),
          price_components: build_price_components(invoice_line_item),
          medication: build_medication(charge_item)
        }.compact
      end

      def extract_date_posted(charge_item)
        charge_item['occurrenceDateTime'] ||
          charge_item.dig('occurrencePeriod', 'start') ||
          charge_item['enteredDate']
      end

      def extract_provider_name(charge_item)
        encounter_ref = charge_item.dig('context', 'reference')
        return nil unless encounter_ref

        encounter_id = extract_id_from_reference(encounter_ref)
        encounter = @encounters[encounter_id]
        encounter&.dig('serviceProvider', 'display')
      end

      def build_price_components(invoice_line_item)
        components = invoice_line_item['priceComponent'] || []
        components.map do |pc|
          {
            type: pc['type'],
            code: pc.dig('code', 'text'),
            amount: pc.dig('amount', 'value')&.to_f
          }
        end
      end

      def build_medication(charge_item)
        services = charge_item['service'] || []
        dispense_ref = services.find { |s| s['reference']&.include?('MedicationDispense') }&.dig('reference')
        return nil unless dispense_ref

        dispense_id = extract_id_from_reference(dispense_ref)
        dispense = @medication_dispenses[dispense_id]
        return nil unless dispense

        medication_ref = dispense.dig('medicationReference', 'reference')
        medication_id = extract_id_from_reference(medication_ref)
        medication = @medications[medication_id]

        {
          medication_name: dispense.dig('medicationReference', 'display') ||
            dispense.dig('medicationCodeableConcept', 'text'),
          rx_number: medication&.dig('identifier', 0, 'id'),
          quantity: dispense.dig('quantity', 'value'),
          days_supply: dispense.dig('daysSupply', 'value')
        }
      end

      def extract_id_from_reference(reference)
        return nil unless reference

        reference.split('/').last
      end
    end
  end
end
