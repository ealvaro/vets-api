# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Lighthouse::HCC::LineItemBuilder do
  describe '#sorted_line_items' do
    it 'returns an empty array when line_items is nil or blank' do
      builder = described_class.new

      expect(builder.sorted_line_items(nil)).to eq([])
      expect(builder.sorted_line_items([])).to eq([])
    end

    it 'merges constructor charge_items with additional_charge_items for lookup' do
      builder = described_class.new(
        charge_items: {
          'ci-base' => { 'code' => { 'text' => 'FROM BASE' } }
        }
      )

      fhir_lines = [
        {
          'chargeItemReference' => { 'reference' => 'ChargeItem/ci-base' },
          'priceComponent' => []
        }
      ]

      additional = {
        'ci-extra' => {
          'code' => { 'text' => 'FROM ADDITIONAL' },
          'occurrenceDateTime' => '2025-02-01T12:00:00Z'
        }
      }

      fhir_lines << {
        'chargeItemReference' => { 'reference' => 'https://example.org/fhir/ChargeItem/ci-extra' },
        'priceComponent' => [{ 'type' => 'base', 'amount' => { 'value' => 1.0 } }]
      }

      result = builder.sorted_line_items(fhir_lines, additional_charge_items: additional)

      expect(result.map { |r| r[:billing_reference] }).to contain_exactly('ci-base', 'ci-extra')
      by_ref = result.index_by { |row| row[:billing_reference] }

      expect(by_ref['ci-base'][:description]).to eq('FROM BASE')
      expect(by_ref['ci-extra'][:description]).to eq('FROM ADDITIONAL')
      expect(by_ref['ci-extra'][:date_posted]).to eq('2025-02-01T12:00:00Z')
      expect(by_ref['ci-extra'][:price_components]).to contain_exactly(
        hash_including(type: 'base', amount: 1.0)
      )
    end

    it 'sorts rows with date_posted newest first, then rows without date_posted after' do
      builder = described_class.new
      fhir_lines = [
        {
          'chargeItemReference' => { 'reference' => 'ChargeItem/old' },
          'priceComponent' => []
        },
        {
          'chargeItemReference' => { 'reference' => 'ChargeItem/new' },
          'priceComponent' => []
        },
        {
          'chargeItemReference' => { 'reference' => 'ChargeItem/no-date' },
          'priceComponent' => []
        }
      ]

      additional = {
        'old' => { 'occurrenceDateTime' => '2025-01-01T00:00:00Z', 'code' => { 'text' => 'A' } },
        'new' => { 'occurrenceDateTime' => '2025-06-01T00:00:00Z', 'code' => { 'text' => 'B' } },
        'no-date' => { 'code' => { 'text' => 'C' } }
      }

      result = builder.sorted_line_items(fhir_lines, additional_charge_items: additional)

      expect(result.map { |r| r[:billing_reference] }).to eq(%w[new old no-date])
    end

    it 'resolves provider_name from encounters when ChargeItem has context' do
      charge_item = {
        'context' => { 'reference' => 'Encounter/enc-1' },
        'code' => { 'text' => 'Visit' },
        'occurrenceDateTime' => '2025-03-01T00:00:00Z'
      }
      encounters = {
        'enc-1' => { 'serviceProvider' => { 'display' => 'Test VA Clinic' } }
      }
      builder = described_class.new(encounters:)

      fhir_lines = [
        {
          'chargeItemReference' => { 'reference' => 'ChargeItem/ci-1' },
          'priceComponent' => []
        }
      ]

      result = builder.sorted_line_items(
        fhir_lines,
        additional_charge_items: { 'ci-1' => charge_item }
      )

      expect(result.first[:provider_name]).to eq('Test VA Clinic')
    end

    it 'builds medication when MedicationDispense and Medication are present' do
      charge_item = {
        'service' => [{ 'reference' => 'MedicationDispense/disp-1' }],
        'code' => { 'text' => 'Rx copay' },
        'occurrenceDateTime' => '2025-04-01T00:00:00Z'
      }
      dispenses = {
        'disp-1' => {
          'medicationReference' => {
            'reference' => 'Medication/med-1',
            'display' => 'Atorvastatin'
          },
          'quantity' => { 'value' => 30 },
          'daysSupply' => { 'value' => 30 }
        }
      }
      medications = {
        'med-1' => { 'identifier' => [{ 'id' => 'RX-999' }] }
      }

      builder = described_class.new(
        medication_dispenses: dispenses,
        medications:
      )

      fhir_lines = [
        {
          'chargeItemReference' => { 'reference' => 'ChargeItem/ci-rx' },
          'priceComponent' => []
        }
      ]

      result = builder.sorted_line_items(
        fhir_lines,
        additional_charge_items: { 'ci-rx' => charge_item }
      )

      med = result.first[:medication]
      expect(med).to include(
        medication_name: 'Atorvastatin',
        rx_number: 'RX-999',
        quantity: 30,
        days_supply: 30
      )
    end

    it 'uses enteredDate when occurrence fields are absent' do
      builder = described_class.new
      fhir_lines = [
        {
          'chargeItemReference' => { 'reference' => 'ChargeItem/ci-entered' },
          'priceComponent' => []
        }
      ]

      result = builder.sorted_line_items(
        fhir_lines,
        additional_charge_items: {
          'ci-entered' => {
            'enteredDate' => '2025-05-14T15:00:00Z',
            'code' => { 'text' => 'Entered only' }
          }
        }
      )

      expect(result.first[:date_posted]).to eq('2025-05-14T15:00:00Z')
    end
  end
end
