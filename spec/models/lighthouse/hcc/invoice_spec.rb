# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Lighthouse::HCC::Invoice do
  subject(:invoice) { described_class.new(params) }

  let(:statement_day_url) do
    'https://api.va.gov/services/fhir/v0/r4/StructureDefinition/account-statementGeneratedDay'
  end

  let(:total_price_component) do
    [
      { 'type' => 'base', 'code' => { 'text' => 'Previous Balance' }, 'amount' => { 'value' => 100.0 } },
      { 'type' => 'surcharge', 'code' => { 'text' => 'Interest Charged' }, 'amount' => { 'value' => 5.24 } },
      { 'type' => 'informational', 'code' => { 'text' => 'Original Amount' }, 'amount' => { 'value' => 60.0 } }
    ]
  end

  let(:account) { { 'extension' => [{ 'url' => statement_day_url, 'valueInteger' => 11 }] } }

  let(:params) do
    {
      'resource' => {
        'id' => 'I2-INVOICE1',
        'date' => '2025-12-11T04:00:00Z',
        'fullUrl' => 'https://api.va.gov/Invoice/I2-INVOICE1',
        'meta' => { 'lastUpdated' => '2025-12-12T00:00:00Z' },
        'issuer' => { 'display' => 'Chalmers P. Wylie Veterans Outpatient Clinic' },
        'facility_id' => 'I2-ORG1',
        'city' => 'Columbus',
        'lineItem' => [
          {
            'chargeItemReference' => { 'reference' => 'ChargeItem/I2-CHARGE1' },
            'priceComponent' => [{ 'amount' => { 'value' => 2.03 } }]
          }
        ],
        'line_items' => [{ billing_reference: 'I2-CHARGE1' }],
        'totalPriceComponent' => total_price_component,
        'account' => account
      }
    }
  end

  describe '.sum_charged_amounts' do
    it 'sums the base and surcharge components' do
      typed_amounts = [['base', 100.0], ['surcharge', 5.24]]

      expect(described_class.sum_charged_amounts(typed_amounts)).to eq(105.24)
    end

    it 'ignores informational components, which restate the charges rather than add to them' do
      typed_amounts = [['base', 76.19], ['informational', 76.19]]

      expect(described_class.sum_charged_amounts(typed_amounts)).to eq(76.19)
    end

    it 'treats a missing amount as zero rather than raising' do
      expect(described_class.sum_charged_amounts([['base', nil]])).to eq(0.0)
    end

    it 'reports zero when there are no components' do
      expect(described_class.sum_charged_amounts([])).to eq(0.0)
    end

    it 'reports zero when the components are absent entirely' do
      expect(described_class.sum_charged_amounts(nil)).to eq(0.0)
    end
  end

  describe '#initialize' do
    it 'assigns the invoice identity and timestamps' do
      expect(invoice).to have_attributes(
        external_id: 'I2-INVOICE1',
        invoice_date: '2025-12-11T04:00:00Z',
        url: 'https://api.va.gov/Invoice/I2-INVOICE1',
        last_updated_at: '2025-12-12T00:00:00Z'
      )
    end

    it 'assigns the facility attributes from the issuer' do
      expect(invoice).to have_attributes(
        facility: 'Chalmers P. Wylie Veterans Outpatient Clinic',
        facility_id: 'I2-ORG1',
        city: 'Columbus'
      )
    end

    it 'takes the latest billing reference from the first line item charge item' do
      expect(invoice.latest_billing_ref).to eq('I2-CHARGE1')
    end

    it 'takes the last credit or debit from the first line item price component' do
      expect(invoice.last_credit_debit).to eq(2.03)
    end

    it 'carries the flattened line items through' do
      expect(invoice.line_items).to eq([{ billing_reference: 'I2-CHARGE1' }])
    end

    context 'when the invoice has no line items' do
      let(:params) { { 'resource' => { 'totalPriceComponent' => total_price_component } } }

      it 'leaves the billing reference and last credit or debit unset' do
        expect(invoice.latest_billing_ref).to be_nil
        expect(invoice.last_credit_debit).to be_nil
      end

      it 'defaults the flattened line items to an empty list' do
        expect(invoice.line_items).to eq([])
      end
    end
  end

  describe 'balances' do
    it 'sums the current balance across the components that are not informational' do
      expect(invoice.current_balance).to eq(105.24)
    end

    it 'reads the previous balance from the Original Amount component' do
      expect(invoice.previous_balance).to eq(60.0)
    end

    it 'sums the previous unpaid balance from the charged components only' do
      expect(invoice.previous_unpaid_balance).to eq(105.24)
    end

    context 'when no component restates the original amount' do
      let(:total_price_component) do
        [{ 'type' => 'base', 'code' => { 'text' => 'Previous Balance' }, 'amount' => { 'value' => 100.0 } }]
      end

      it 'leaves the previous balance unset rather than reporting zero' do
        expect(invoice.previous_balance).to be_nil
      end
    end

    context 'when the only component is informational' do
      let(:total_price_component) do
        [{ 'type' => 'informational', 'code' => { 'text' => 'Total Charge' }, 'amount' => { 'value' => 76.19 } }]
      end

      it 'reports a zero current balance rather than counting the restatement' do
        expect(invoice.current_balance).to eq(0.0)
      end

      it 'reports a zero previous unpaid balance' do
        expect(invoice.previous_unpaid_balance).to eq(0.0)
      end
    end
  end

  describe 'statement generated day' do
    it 'reads the day from the account statementGeneratedDay extension' do
      expect(invoice.statement_generated_day).to eq(11)
    end

    context 'when the invoice carries no account' do
      let(:account) { nil }

      it 'leaves the day unset' do
        expect(invoice.statement_generated_day).to be_nil
      end
    end

    context 'when the account carries no statementGeneratedDay extension' do
      let(:account) { { 'extension' => [{ 'url' => 'https://api.va.gov/other', 'valueInteger' => 3 }] } }

      it 'leaves the day unset' do
        expect(invoice.statement_generated_day).to be_nil
      end
    end
  end
end
