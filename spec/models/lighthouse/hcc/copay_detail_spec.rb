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
              'identifier' => [{ 'type' => { 'text' => 'Bill Number' }, 'value' => '573-JAN-TEST' }],
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
              ],
              'lineItem' => [
                {
                  'chargeItemReference' => {
                    'reference' => 'https://test.gov/services/health-care-costs-coverage/v0/r4/ChargeItem/4-6cXQjkA9CC',
                    'display' => 'DG OPT COPAY NEW'
                  },
                  'priceComponent' => [
                    { 'type' => 'base', 'code' => { 'text' => 'Total Charge' }, 'amount' => { 'value' => 76.19 } }
                  ]
                },
                {
                  'chargeItemReference' => {
                    'reference' => 'https://test.gov/services/health-care-costs-coverage/v0/r4/ChargeItem/4-6cXQm5UhWz',
                    'display' => 'INTEREST/ADM. CHARGE'
                  },
                  'priceComponent' => [
                    {
                      'type' => 'surcharge',
                      'code' => { 'text' => 'Interest Charged' }, 'amount' => { 'value' => 0.99 }
                    },
                    {
                      'type' => 'surcharge',
                      'code' => { 'text' => 'Administrative Charged' }, 'amount' => { 'value' => 0.59 }
                    },
                    {
                      'type' => 'informational',
                      'code' => { 'text' => 'Total Charge' }, 'amount' => { 'value' => 1.58 }
                    }
                  ]
                },
                {
                  'chargeItemReference' => {
                    'reference' => 'https://test.gov/services/health-care-costs-coverage/v0/r4/ChargeItem/4-6cXQjkAu53',
                    'display' => 'INTEREST/ADM. CHARGE'
                  },
                  'priceComponent' => [
                    {
                      'type' => 'surcharge',
                      'code' => { 'text' => 'Interest Charged' }, 'amount' => { 'value' => 0.99 }
                    },
                    {
                      'type' => 'surcharge',
                      'code' => { 'text' => 'Administrative Charged' }, 'amount' => { 'value' => 0.59 }
                    },
                    {
                      'type' => 'informational',
                      'code' => { 'text' => 'Total Charge' }, 'amount' => { 'value' => 1.58 }
                    }
                  ]
                }
              ],
              '_associated_charge_items' => {
                '4-6cXQjkA9CC' => {
                  'id' => '4-6cXQjkA9CC',
                  'code' => { 'text' => 'OUTPATIENT CARE(NSC)' },
                  'enteredDate' => '2025-05-14T15:00:00Z'
                },
                '4-6cXQm5UhWz' => {
                  'id' => '4-6cXQm5UhWz',
                  'code' => { 'text' => 'INTEREST/ADM. CHARGE' },
                  'enteredDate' => '2025-05-13T12:00:00Z'
                },
                '4-6cXQjkAu53' => {
                  'id' => '4-6cXQjkAu53',
                  'code' => { 'text' => 'INTEREST/ADM. CHARGE' },
                  'enteredDate' => '2025-05-12T12:00:00Z'
                }
              }
            }
          },
          {
            'resource' => {
              'id' => '123', 'date' => '2026-02-01T14:32:00-05:00',
              'identifier' => [{ 'type' => { 'text' => 'Bill Number' }, 'value' => '573-FEB-TEST' }],
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

      it 'resolves associated statement line item description and date from resource _associated_charge_items' do
        stmt = subject.associated_statements.find { |s| s['composite_id'] == '4-5pFm5Av0PHt-1-2026' }
        first = stmt['line_items'].first

        expect(first[:description]).to eq('OUTPATIENT CARE(NSC)')
        expect(first[:date_posted]).to eq('2025-05-14T15:00:00Z')
      end

      it 'creates associated_statements with bill_number from extract_bill_number (same as payments)' do
        expect(subject.associated_statements).to match(
          [
            {
              'id' => '123',
              'composite_id' => '4-5pFm5Av0PHt-2-2026',
              'date' => 'February 1, 2026',
              'bill_number' => '573-FEB-TEST',
              'charge_items' => [],
              'line_items' => []
            },
            {
              'id' => '123',
              'composite_id' => '4-5pFm5Av0PHt-1-2026',
              'date' => 'January 1, 2026',
              'bill_number' => '573-JAN-TEST',
              'charge_items' => array_including(a_hash_including('id' => '4-6c9ZE23XQjkALyz')),
              'line_items' => a_collection_including(a_hash_including(billing_reference: '4-6cXQjkA9CC'))
            }
          ]
        )
      end

      it 'creates associated_invoices' do
        expect(subject.associated_invoices).to match(
          [
            a_hash_including(
              'id' => '123',
              'composite_id' => '4-5pFm5Av0PHt-2-2026',
              'date' => 'February 1, 2026',
              'charge_items' => an_instance_of(Array),
              'line_items' => an_instance_of(Array)
            ),
            a_hash_including(
              'id' => '123',
              'composite_id' => '4-5pFm5Av0PHt-1-2026',
              'date' => 'January 1, 2026',
              'charge_items' => a_collection_including(
                a_hash_including('id' => '4-6c9ZE23XQjkALyz')
              ),
              'line_items' => a_collection_including(
                a_hash_including(
                  billing_reference: '4-6cXQjkA9CC'
                )
              )
            )
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

      it 'sorts line_items in descending order by date_posted' do
        invoice_data_with_line_items = {
          'id' => 'invoice-456',
          'date' => '2025-06-01T20:29:47Z',
          'lineItem' => [
            {
              'chargeItemReference' => { 'reference' => 'ChargeItem/old-item' },
              'priceComponent' => [{ 'type' => 'base', 'amount' => { 'value' => 50.0 } }]
            },
            {
              'chargeItemReference' => { 'reference' => 'ChargeItem/new-item' },
              'priceComponent' => [{ 'type' => 'base', 'amount' => { 'value' => 75.0 } }]
            },
            {
              'chargeItemReference' => { 'reference' => 'ChargeItem/middle-item' },
              'priceComponent' => [{ 'type' => 'base', 'amount' => { 'value' => 60.0 } }]
            }
          ]
        }

        charge_items_with_dates = {
          'old-item' => {
            'occurrenceDateTime' => '2025-01-01T10:00:00Z',
            'code' => { 'text' => 'Old Service' }
          },
          'new-item' => {
            'occurrenceDateTime' => '2025-06-01T10:00:00Z',
            'code' => { 'text' => 'New Service' }
          },
          'middle-item' => {
            'occurrenceDateTime' => '2025-03-01T10:00:00Z',
            'code' => { 'text' => 'Middle Service' }
          }
        }

        detail = described_class.new(
          invoice_data: invoice_data_with_line_items,
          charge_items: charge_items_with_dates,
          account_data: nil,
          facility_address: nil,
          patient_data: nil,
          associated_statements: []
        )

        dates = detail.line_items.map { |li| li[:date_posted] }
        expect(dates).to eq(
          [
            '2025-06-01T10:00:00Z',
            '2025-03-01T10:00:00Z',
            '2025-01-01T10:00:00Z'
          ]
        )
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

      it 'sets bill_number to nil when extract_bill_number finds no Bill Number identifier' do
        invoice_data = {
          'id' => 'inv-1',
          'date' => '2025-06-01T20:29:47Z',
          'issuer' => { 'display' => 'VA', 'reference' => 'Organization/4-5pFm5Av0PHt' }
        }
        associated_statements = [
          {
            'resource' => {
              'id' => 'assoc-1',
              'date' => '2026-03-01T12:00:00Z',
              'issuer' => { 'reference' => 'Organization/4-5pFm5Av0PHt' },
              'charge_items' => [],
              'lineItem' => []
            }
          }
        ]
        detail = described_class.new(invoice_data:, associated_statements:)

        expect(detail.associated_statements.first['bill_number']).to be_nil
      end
    end
  end

  describe '#sorted_line_items' do
    it 'uses additional_charge_items keyword args for ChargeItem lookup (not positional)' do
      detail = described_class.new(
        invoice_data: { 'id' => 'inv', 'date' => '2026-06-01T00:00:00Z' },
        associated_statements: []
      )

      line_items = [
        {
          'chargeItemReference' => {
            'reference' => 'https://api.gov/fhir/r4/ChargeItem/ci-from-bundle'
          },
          'priceComponent' => [{ 'type' => 'base', 'code' => { 'text' => 'Amount' }, 'amount' => { 'value' => 10.0 } }]
        }
      ]

      additional_charge_items = {
        'ci-from-bundle' => {
          'code' => { 'text' => 'DESCRIPTION FROM BUNDLE MAP' },
          'enteredDate' => '2025-05-14T15:00:00Z'
        }
      }

      result = detail.send(:sorted_line_items, line_items, additional_charge_items:)

      expect(result.first[:description]).to eq('DESCRIPTION FROM BUNDLE MAP')
      expect(result.first[:date_posted]).to eq('2025-05-14T15:00:00Z')
    end
  end
end
