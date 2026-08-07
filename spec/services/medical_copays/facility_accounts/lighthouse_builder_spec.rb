# frozen_string_literal: true

require 'rails_helper'

RSpec.describe MedicalCopays::FacilityAccounts::LighthouseBuilder do
  subject(:builder) { described_class.new(lighthouse_service:) }

  let(:lighthouse_service) { instance_double(MedicalCopays::LighthouseIntegration::Service) }
  let(:organization_id) { '4-5pFm5BMGzyD' }
  let(:facility_identifier_value) { 'vha_896' }
  let(:organization_resource) { org_resource(organization_id, facility_identifier_value) }

  before do
    stub_organization(organization_id, organization_resource)
  end

  def stub_organization(org_id, resource)
    allow(lighthouse_service).to receive(:fetch_organization)
      .with(org_id, described_class::ORG_CACHE_STATSD_KEY)
      .and_return(resource)
  end

  def org_resource(org_id, facility_identifier)
    identifiers = [{ 'system' => 'http://hl7.org/fhir/sid/us-npi', 'value' => '0221760022' }]
    if facility_identifier
      identifiers << { 'system' => described_class::FACILITY_IDENTIFIER_SYSTEM, 'value' => facility_identifier }
    end
    { 'resourceType' => 'Organization', 'id' => org_id, 'identifier' => identifiers, 'name' => 'TEST VAMC' }
  end

  def invoice_double(**overrides)
    defaults = {
      external_id: 'I2-INVOICE1',
      facility_id: organization_id,
      facility: 'Chalmers P. Wylie Veterans Outpatient Clinic',
      current_balance: 105.24,
      invoice_date: '2025-12-20T04:00:00Z',
      statement_generated_day: 11
    }
    instance_double(Lighthouse::HCC::Invoice, **defaults.merge(overrides))
  end

  # Keys mirror LineItemBuilder#build_line_item
  def line_item_hash(**overrides)
    {
      billing_reference: 'I2-CHARGE1',
      date_posted: '2025-11-20T04:00:00Z',
      description: 'NX RX #2719324 (30 days)',
      provider_name: 'COLUMBUS VAMC',
      price_components: [{ type: 'base', code: 'Copay', amount: 2.03 }],
      medication: { medication_name: 'ATORVASTATIN', rx_number: '2719324', quantity: 30, days_supply: 30 }
    }.merge(overrides)
  end

  # Keys mirror CopayDetail#build_payment
  def payment_hash(**overrides)
    { payment_id: 'P2-PAYMENT1', payment_date: '2025-11-28', payment_amount: 10.0 }.merge(overrides)
  end

  def detail_double(**overrides)
    defaults = {
      account_number: '57 0000 0001 97750 IPOAD',
      bill_number: 'K700DAC53',
      line_items: [line_item_hash],
      payments: [payment_hash]
    }
    instance_double(Lighthouse::HCC::CopayDetail, **defaults.merge(overrides))
  end

  describe '#build_facility_accounts' do
    let(:invoice) { invoice_double }
    let(:invoices) { [invoice] }
    let(:bundle) { instance_double(Lighthouse::HCC::Bundle, entries: invoices) }
    let(:accounts) { builder.build_facility_accounts }

    before do
      allow(lighthouse_service).to receive(:list_months).and_return(bundle)
    end

    it 'builds a facility account per station with the summed current balance' do
      expect(accounts.size).to eq(1)
      expect(accounts.first).to have_attributes(station_id: '896', current_balance: 105.24)
    end

    it 'names the facility from the invoice issuer display' do
      expect(accounts.first.facility_name).to eq('Chalmers P. Wylie Veterans Outpatient Clinic')
    end

    it 'fetches each organization once across station and name lookups' do
      accounts

      expect(lighthouse_service).to have_received(:fetch_organization)
        .with(organization_id, described_class::ORG_CACHE_STATSD_KEY).once
    end

    it 'constructs the statement date from the latest invoice month and statement day, due 25 days later' do
      expect(accounts.first.statement_date).to eq(Date.new(2025, 12, 11))
      expect(accounts.first.due_date).to eq(Date.new(2026, 1, 5))
    end

    it 'marks accounts not cerner, since cerner users never reach the Lighthouse path' do
      expect(accounts.first.is_cerner).to be(false)
    end

    context 'when an older statement cycle is unpaid' do
      let(:invoices) { [invoice, invoice_double(invoice_date: '2025-11-20T04:00:00Z', current_balance: 50.0)] }

      before { Timecop.freeze(Time.zone.local(2025, 12, 30)) }
      after { Timecop.return }

      it 'reports the past due portion of the current balance' do
        expect(accounts.first.current_balance).to eq(155.24)
        expect(accounts.first.past_due_balance).to eq(50.0)
      end
    end

    context 'when invoices span organizations that share a parent station' do
      let(:parent_org_id) { '4-parent640' }
      let(:division_org_id) { '4-division640A0' }
      let(:invoices) do
        [
          invoice,
          invoice_double(facility_id: parent_org_id, current_balance: 0.1),
          invoice_double(facility_id: division_org_id, current_balance: 0.2)
        ]
      end

      before do
        stub_organization(parent_org_id, org_resource(parent_org_id, 'vha_640'))
        stub_organization(division_org_id, org_resource(division_org_id, 'vha_640A0'))
      end

      it 'merges divisions into their parent station and rounds the summed balance' do
        expect(accounts.map(&:station_id)).to contain_exactly('896', '640')
        merged_account = accounts.find { |account| account.station_id == '640' }
        expect(merged_account.current_balance).to eq(0.3)
      end
    end

    context 'when an organization has no va-facility-identifier' do
      let(:unresolvable_org_id) { '4-noFacilityId' }
      let(:invoices) { [invoice, invoice_double(facility_id: unresolvable_org_id, current_balance: 50.0)] }

      before do
        stub_organization(unresolvable_org_id, org_resource(unresolvable_org_id, nil))
      end

      it 'excludes invoices that cannot resolve to a station' do
        expect(accounts.map(&:station_id)).to contain_exactly('896')
      end

      it 'logs a warning naming the unresolvable organization' do
        allow(Rails.logger).to receive(:warn)

        accounts

        expect(Rails.logger).to have_received(:warn)
          .with("FacilityAccounts::LighthouseBuilder no station id for orgs: #{unresolvable_org_id}, " \
                'excluding 1 invoice(s)')
      end
    end

    context 'when an organization fetch has degraded to nil' do
      let(:failing_org_id) { '4-failingOrg' }
      let(:invoices) { [invoice, invoice_double(facility_id: failing_org_id, current_balance: 12.0)] }

      before do
        stub_organization(failing_org_id, nil)
      end

      it 'degrades to the facilities that still resolve' do
        expect(accounts.map(&:station_id)).to contain_exactly('896')
      end

      it 'attempts the failing organization only once' do
        accounts

        expect(lighthouse_service).to have_received(:fetch_organization)
          .with(failing_org_id, described_class::ORG_CACHE_STATSD_KEY).once
      end
    end
  end

  describe '#build_facility_account' do
    let(:invoice) { invoice_double }
    let(:invoices) { [invoice] }
    let(:bundle) { instance_double(Lighthouse::HCC::Bundle, entries: invoices) }
    let(:detail) { detail_double }
    let(:account) { builder.build_facility_account('896') }

    before do
      allow(lighthouse_service).to receive(:list_months).and_return(bundle)
      allow(lighthouse_service).to receive(:get_detail)
        .with(id: 'I2-INVOICE1', include_associated: false).and_return(detail)
      Timecop.freeze(Time.zone.local(2025, 12, 15))
    end

    after { Timecop.return }

    it 'builds the requested station account from its invoices' do
      expect(account).to have_attributes(
        station_id: '896',
        facility_name: 'Chalmers P. Wylie Veterans Outpatient Clinic',
        is_cerner: false,
        account_number: '57 0000 0001 97750 IPOAD',
        current_balance: 105.24,
        past_due_balance: 0.0,
        statement_date: Date.new(2025, 12, 11),
        due_date: Date.new(2026, 1, 5)
      )
    end

    it 'returns nothing for a station the veteran has no invoices at' do
      expect(builder.build_facility_account('123')).to be_nil
    end

    it 'maps charge rows from the invoice line items' do
      charge = account.transactions.find { |transaction| transaction[:type] == 'charge' }

      expect(charge).to eq(
        id: 'I2-CHARGE1',
        type: 'charge',
        date: '2025-11-20',
        description: 'NX RX #2719324 (30 days)',
        amount: 2.03,
        billing_reference: 'K700DAC53',
        provider: 'COLUMBUS VAMC',
        medication: { medication_name: 'ATORVASTATIN', rx_number: '2719324', quantity: 30, days_supply: 30 }
      )
    end

    it 'maps payment rows without inventing a description' do
      payment = account.transactions.find { |transaction| transaction[:type] == 'payment' }

      expect(payment).to eq(id: 'P2-PAYMENT1', type: 'payment', date: '2025-11-28', amount: 10.0)
    end

    it 'orders charges and payments together, newest first' do
      expect(account.transactions.map { |transaction| transaction[:date] })
        .to eq(%w[2025-11-28 2025-11-20])
    end

    describe 'charge amount' do
      # Shapes taken from spec/fixtures/lighthouse/hcc/bundle.json
      def charge_amount_for(price_components)
        allow(lighthouse_service).to receive(:get_detail)
          .with(id: 'I2-INVOICE1', include_associated: false)
          .and_return(detail_double(line_items: [line_item_hash(price_components:)], payments: []))

        builder.build_facility_account('896').transactions.first[:amount]
      end

      it 'totals the charged components rather than reading the first one' do
        components = [
          { type: 'surcharge', code: 'Interest Charged', amount: 0.99 },
          { type: 'surcharge', code: 'Administrative Charged', amount: 0.59 },
          { type: 'informational', code: 'Total Charge', amount: 1.58 }
        ]

        expect(charge_amount_for(components)).to eq(1.58)
      end

      it 'takes the single component when a charge is not broken out' do
        expect(charge_amount_for([{ type: 'base', code: 'Total Charge', amount: 76.19 }])).to eq(76.19)
      end

      it 'reports zero when a charge carries no priced components' do
        expect(charge_amount_for([])).to eq(0.0)
      end
    end

    describe 'transaction dates' do
      it 'normalizes charge timestamps to a plain date' do
        charge = account.transactions.find { |transaction| transaction[:type] == 'charge' }

        expect(charge[:date]).to eq('2025-11-20')
      end

      context 'when a charge timestamp carries a UTC offset' do
        let(:detail) do
          detail_double(line_items: [line_item_hash(date_posted: '2025-11-20T23:00:00-05:00')], payments: [])
        end

        it 'keeps the date the charge was posted rather than shifting it to UTC' do
          expect(account.transactions.first[:date]).to eq('2025-11-20')
        end
      end

      context 'when charges and payments fall across offsets and formats' do
        let(:detail) do
          detail_double(
            line_items: [
              line_item_hash(billing_reference: 'I2-EARLY', date_posted: '2025-11-20T23:00:00-05:00'),
              line_item_hash(billing_reference: 'I2-LATE', date_posted: '2025-12-01T09:30:00Z')
            ],
            payments: [payment_hash(payment_date: '2025-11-28')]
          )
        end

        it 'orders on the normalized dates, newest first' do
          expect(account.transactions.map { |transaction| transaction[:date] })
            .to eq(%w[2025-12-01 2025-11-28 2025-11-20])
        end
      end
    end

    context 'when a payment amount arrives negative' do
      let(:detail) { detail_double(payments: [payment_hash(payment_amount: -10.0)]) }

      it 'reports it positive, since the type carries the credit' do
        payment = account.transactions.find { |transaction| transaction[:type] == 'payment' }

        expect(payment[:amount]).to eq(10.0)
      end
    end

    context 'when a charge item did not come back from Lighthouse' do
      let(:unenriched_line_item) do
        { billing_reference: 'I2-CHARGE2', price_components: [{ type: 'base', amount: 5.0 }] }
      end
      let(:detail) { detail_double(line_items: [line_item_hash, unenriched_line_item], payments: []) }

      it 'keeps the row so the amounts still reconcile, and sorts it last' do
        expect(account.transactions.last).to include(id: 'I2-CHARGE2', amount: 5.0, date: nil, description: nil)
      end

      it 'logs the charge items it could not label' do
        allow(Rails.logger).to receive(:warn)

        account

        expect(Rails.logger).to have_received(:warn)
          .with('FacilityAccounts::LighthouseBuilder no charge item for: I2-CHARGE2, 1 unlabeled transaction(s)')
      end
    end

    context 'when the station has invoices from several cycles' do
      let(:older_invoice) do
        invoice_double(external_id: 'I2-INVOICE2', current_balance: 50.0, invoice_date: '2025-11-20T04:00:00Z')
      end
      let(:invoices) { [invoice, older_invoice] }

      before do
        allow(lighthouse_service).to receive(:get_detail).with(id: 'I2-INVOICE2', include_associated: false).and_return(
          detail_double(line_items: [line_item_hash(billing_reference: 'I2-CHARGE9',
                                                    date_posted: '2025-10-15T04:00:00Z')], payments: [])
        )
      end

      it 'sums the balances and merges both ledgers into one list' do
        expect(account.current_balance).to eq(155.24)
        expect(account.transactions.map { |transaction| transaction[:id] })
          .to eq(%w[P2-PAYMENT1 I2-CHARGE1 I2-CHARGE9])
      end
    end

    it 'leaves the account number and transactions off the index representation' do
      index_account = builder.build_facility_accounts.first

      expect(index_account.account_number).to be_nil
      expect(index_account.transactions).to be_nil
      expect(lighthouse_service).not_to have_received(:get_detail)
    end
  end

  describe '#get_station_id' do
    it 'resolves an organization to the bare station id from its Facility ID identifier' do
      expect(builder.send(:get_station_id, organization_id)).to eq('896')
    end

    context 'when the identifier value is division-suffixed' do
      let(:facility_identifier_value) { 'vha_640A0' }

      it 'truncates to the parent station id' do
        expect(builder.send(:get_station_id, organization_id)).to eq('640')
      end
    end

    context 'when the identifier value is shorter than a parent station' do
      let(:facility_identifier_value) { 'vha_6' }

      it 'excludes the value rather than resolving a partial station id' do
        expect(builder.send(:get_station_id, organization_id)).to be_nil
      end
    end

    context 'when the organization has no Facility ID identifier' do
      let(:organization_resource) { org_resource(organization_id, nil) }

      it 'returns nil rather than falling back to the org FHIR id' do
        expect(builder.send(:get_station_id, organization_id)).to be_nil
      end
    end
  end
end
