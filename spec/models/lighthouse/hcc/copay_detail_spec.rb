# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Lighthouse::HCC::CopayDetail do
  describe 'initialization' do
    context 'with valid invoice data' do
      subject do
        described_class.new(invoice_data:, account_data:, facility_address:, patient_data:, associated_statements:)
      end

      let(:invoice_data) do
        {
          'id' => 'invoice-123',
          'issuer' => { 'display' => 'VA Medical Center' },
          'identifier' => [{ 'value' => 'BILL-001' }],
          'status' => 'issued',
          '_status' => { 'valueCodeableConcept' => { 'text' => 'Active' } },
          'date' => '2025-06-01T20:29:47Z'
        }
      end

      let(:account_data) do
        { 'identifier' => [{ 'value' => 'ACCT-999' }] }
      end

      let(:facility_address) do
        {
          address_line1: '123 Test',
          address_line2: nil,
          address_line3: nil,
          city: 'Test City',
          state: 'FL',
          postalCode: '12345'
        }
      end

      let(:associated_statements) do
        [
          {
            'resource' => {
              'id' => '123', 'date' => '2026-01-01T14:32:00-05:00',
              'issuer' => {
                'reference' => 'https://api.gov/services/health-care-costs-coverage/v0/r4/Organization/4-5pFm5Av0PHt',
                'display' => 'TEST VAMC'
              },
              'charge_items' => [
                {
                  'id' => '4-6c9ZE23XQjkALyz',
                  'last_updated_at' => '2025-01-30T00:00:00Z',
                  'status' => 'billed',
                  'code' => 'INTEREST/ADM. CHARGE',
                  'occurrence_date_time' => '2025-01-29T17:10:47Z',
                  'entered_date' => '2025-01-30T17:10:47Z'
                },
                {
                  'id' => '4-6c9ZE23XQm5UhWz',
                  'last_updated_at' => '2024-12-30T00:00:00Z',
                  'status' => 'billed',
                  'code' => 'INTEREST/ADM. CHARGE',
                  'occurrence_date_time' => '2024-12-29T17:10:47Z',
                  'entered_date' => '2024-12-30T17:10:47Z'
                }
              ]
            }
          },
          {
            'resource' => {
              'id' => '123', 'date' => '2026-02-01T14:32:00-05:00',
              'issuer' => {
                'reference' => 'https://api.gov/services/health-care-costs-coverage/v0/r4/Organization/4-5pFm5Av0PHt',
                'display' => 'TEST VAMC'
              },
              'charge_items' => []
            }
          }
        ]
      end

      let(:patient_data) do
        {
          'resourceType' => 'Bundle',
          'entry' => [
            {
              'resource' => {
                'resourceType' => 'Patient',
                'name' => [{ 'family' => 'DOE', 'given' => %w[JOHN MIDDLE] }],
                'address' => [
                  {
                    'line' => ['123 MAIN ST', 'APT 1'],
                    'city' => 'ANYTOWN',
                    'state' => 'VA',
                    'postalCode' => '12345'
                  }
                ]
              }
            }
          ]
        }
      end

      it 'extracts basic attributes from invoice data' do
        expect(subject.external_id).to eq('invoice-123')
        expect(subject.facility).to include(
          'name' => 'VA Medical Center',
          'address' => include(
            'address_line1' => '123 Test',
            'city' => 'Test City',
            'state' => 'FL',
            'postalCode' => '12345'
          )
        )
        expect(subject.bill_number).to eq('BILL-001')
        expect(subject.status).to eq('issued')
        expect(subject.status_description).to eq('Active')
        expect(subject.invoice_date).to eq('2025-06-01T20:29:47Z')
      end

      it 'extracts account number from account data' do
        expect(subject.account_number).to eq('ACCT-999')
      end

      it 'creates associated_statements' do
        expect(subject.associated_statements).to match(
          [
            {
              'id' => '123',
              'composite_id' => '4-5pFm5Av0PHt-2-2026',
              'date' => 'February 1, 2026',
              'charge_items' => []
            },
            {
              'id' => '123',
              'composite_id' => '4-5pFm5Av0PHt-1-2026',
              'date' => 'January 1, 2026',
              'charge_items' => array_including(a_hash_including('id' => '4-6c9ZE23XQjkALyz'))
            }
          ]
        )
      end

      it 'creates associated_invoices' do
        expect(subject.associated_invoices).to match(
          [
            {
              'id' => '123',
              'composite_id' => '4-5pFm5Av0PHt-2-2026',
              'date' => 'February 1, 2026',
              'charge_items' => an_instance_of(Array)
            },
            {
              'id' => '123',
              'composite_id' => '4-5pFm5Av0PHt-1-2026',
              'date' => 'January 1, 2026',
              'charge_items' => array_including(a_hash_including('id' => '4-6c9ZE23XQjkALyz'))
            }
          ]
        )
      end

      it 'calculates payment due date as invoice date plus 30 days' do
        expect(subject.payment_due_date).to eq('2025-07-01')
      end

      it 'extracts patient data from patient FHIR bundle' do
        expect(subject.patient).to include(
          'first_name' => 'JOHN',
          'middle_name' => 'MIDDLE',
          'last_name' => 'DOE',
          'address' => include(
            'address_line1' => '123 MAIN ST',
            'address_line2' => 'APT 1',
            'address_line3' => nil,
            'city' => 'ANYTOWN',
            'state' => 'VA',
            'postalCode' => '12345'
          )
        )
      end
    end

    context 'with missing or invalid data' do
      it 'handles nil invoice_date' do
        invoice_data = { 'id' => 'test-123', 'date' => nil }
        detail = described_class.new(invoice_data:)

        expect(detail.payment_due_date).to be_nil
      end

      it 'handles invalid invoice_date format' do
        invoice_data = { 'id' => 'test-123', 'date' => 'not-a-date' }
        detail = described_class.new(invoice_data:)

        expect(detail.payment_due_date).to be_nil
      end

      it 'handles nil account_data' do
        invoice_data = { 'id' => 'test-123' }
        detail = described_class.new(invoice_data:, account_data: nil)

        expect(detail.account_number).to be_nil
      end

      it 'handles missing nested keys gracefully' do
        invoice_data = { 'id' => 'test-123' }
        detail = described_class.new(invoice_data:)

        expect(detail.facility).to eq({ 'name' => nil, 'address' => nil })
        expect(detail.bill_number).to be_nil
        expect(detail.status_description).to be_nil
      end

      it 'defaults line_items and payments to empty arrays' do
        invoice_data = { 'id' => 'test-123' }
        detail = described_class.new(invoice_data:)

        expect(detail.line_items).to eq([])
        expect(detail.payments).to eq([])
      end

      it 'handles nil patient_data' do
        invoice_data = { 'id' => 'test-123' }
        detail = described_class.new(invoice_data:, patient_data: nil)

        expect(detail.patient).to be_nil
      end

      it 'handles empty patient bundle' do
        invoice_data = { 'id' => 'test-123' }
        patient_data = { 'resourceType' => 'Bundle', 'entry' => [] }
        detail = described_class.new(invoice_data:, patient_data:)

        expect(detail.patient).to be_nil
      end

      it 'handles patient data with missing name and address' do
        invoice_data = { 'id' => 'test-123' }
        patient_data = {
          'resourceType' => 'Bundle',
          'entry' => [{ 'resource' => { 'resourceType' => 'Patient' } }]
        }
        detail = described_class.new(invoice_data:, patient_data:)

        expect(detail.patient).to include(
          'first_name' => nil,
          'middle_name' => nil,
          'last_name' => nil,
          'address' => include(
            'address_line1' => nil,
            'city' => nil,
            'state' => nil,
            'postalCode' => nil
          )
        )
      end
    end
  end
end
