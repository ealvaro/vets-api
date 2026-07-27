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
      facility_id: organization_id,
      facility: 'Chalmers P. Wylie Veterans Outpatient Clinic',
      current_balance: 105.24,
      invoice_date: '2025-12-20T04:00:00Z',
      statement_generated_day: 11
    }
    instance_double(Lighthouse::HCC::Invoice, **defaults.merge(overrides))
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
