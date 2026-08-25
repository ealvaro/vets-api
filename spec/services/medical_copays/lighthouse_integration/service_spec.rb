# frozen_string_literal: true

require 'rails_helper'

RSpec.describe MedicalCopays::LighthouseIntegration::Service do
  let(:mock_accounts) do
    {
      'account-123' => {
        'id' => 'account-123',
        'status' => 'active',
        'balance' => 100.0
      },
      '4-O3d8XK44ejMS' => {
        'id' => '4-O3d8XK44ejMS',
        'status' => 'active',
        'balance' => 75.72
      },
      '4-Nsb4Vwsulhk8' => {
        'id' => '4-Nsb4Vwsulhk8',
        'status' => 'active',
        'balance' => 100.0
      }
    }
  end

  describe '#fetch_organization' do
    let(:service) { described_class.new('123') }
    let(:memory_store) { ActiveSupport::Cache::MemoryStore.new }
    let(:organization_id) { '4-5pFm5BMGzyD' }
    let(:organization_resource) do
      {
        'resourceType' => 'Organization',
        'id' => organization_id,
        'address' => [
          {
            'line' => ['8300 RED BUG LAKE RD'],
            'city' => 'OVIEDO',
            'state' => 'FL',
            'postalCode' => '327656801'
          }
        ]
      }
    end
    let(:organization_bundle) { { 'entry' => [{ 'resource' => organization_resource }] } }
    let(:organization_client) do
      instance_double(Lighthouse::HealthcareCostAndCoverage::Organization::Service, read: organization_bundle)
    end

    before do
      allow(Rails).to receive(:cache).and_return(memory_store)
      allow(service).to receive(:organization_service).and_return(organization_client)
    end

    it 'reads upstream once and serves repeat lookups from the cache' do
      2.times { service.fetch_organization(organization_id) }

      expect(organization_client).to have_received(:read).once
    end

    it 'records a miss on the first lookup and a hit on the second' do
      expect { service.fetch_organization(organization_id) }
        .to trigger_statsd_increment('api.mcp.lighthouse.org_cache', tags: ['result:miss'])
      expect { service.fetch_organization(organization_id) }
        .to trigger_statsd_increment('api.mcp.lighthouse.org_cache', tags: ['result:hit'])
    end

    it 'records the metric under a caller-provided key' do
      expect { service.fetch_organization(organization_id, 'api.mcp.facility_accounts.org_cache') }
        .to trigger_statsd_increment('api.mcp.facility_accounts.org_cache', tags: ['result:miss'])
    end

    it 'returns nil without a lookup when the org id is blank' do
      expect(service.fetch_organization(nil)).to be_nil
      expect(organization_client).not_to have_received(:read)
    end

    context 'when Lighthouse returns no organization' do
      let(:organization_bundle) { { 'entry' => [] } }

      it 'does not cache the empty result' do
        2.times { service.fetch_organization(organization_id) }

        expect(organization_client).to have_received(:read).twice
        expect(memory_store.exist?("lighthouse:org:#{organization_id}")).to be(false)
      end
    end

    context 'when the upstream read fails' do
      before do
        allow(organization_client).to receive(:read).and_raise(Common::Exceptions::BackendServiceException)
        allow(Rails.logger).to receive(:warn)
      end

      it 'degrades to nil instead of raising' do
        expect(service.fetch_organization(organization_id)).to be_nil
      end

      it 'logs the failure class and counts the degradation' do
        expect { service.fetch_organization(organization_id) }
          .to trigger_statsd_increment('api.mcp.lighthouse.org_fetch_degraded')

        expect(Rails.logger).to have_received(:warn)
          .with('OrganizationHelper fetch_organization failed for ' \
                "#{organization_id}: Common::Exceptions::BackendServiceException")
      end

      it 'does not cache the failure' do
        2.times { service.fetch_organization(organization_id) }

        expect(organization_client).to have_received(:read).twice
        expect(memory_store.exist?("lighthouse:org:#{organization_id}")).to be(false)
      end
    end
  end

  describe 'StatsD metrics' do
    let(:service) { described_class.new('123') }

    describe '#list' do
      let(:raw_invoices) do
        {
          'entry' => [
            {
              'resource' => {
                'id' => 'invoice-1',
                'issuer' => { 'reference' => 'Organization/org-123' },
                'account' => { 'reference' => 'Account/account-123' }
              }
            }
          ],
          'link' => [],
          'total' => 1
        }
      end
      let(:mock_bundle) { instance_double(Lighthouse::HCC::Bundle) }

      context 'on success' do
        before do
          allow(service).to receive_messages(
            invoice_service: double(list: raw_invoices),
            fetch_accounts_for_invoices: mock_accounts,
            retrieve_organization_address: {
              city: 'Tampa',
              address_line1: '123 Test St',
              address_line2: nil,
              address_line3: nil,
              state: 'FL',
              postalCode: '33601'
            }
          )
          allow(Lighthouse::HCC::Invoice).to receive(:new).and_return(double)
          allow(Lighthouse::HCC::Bundle).to receive(:new).and_return(mock_bundle)
        end

        it 'increments initiated metric' do
          expect { service.list(count: 10, page: 1) }
            .to trigger_statsd_increment('api.mcp.lighthouse.list.initiated')
        end

        it 'increments success metric' do
          expect { service.list(count: 10, page: 1) }
            .to trigger_statsd_increment('api.mcp.lighthouse.list.success')
        end

        it 'measures latency' do
          expect { service.list(count: 10, page: 1) }
            .to trigger_statsd_measure('api.mcp.lighthouse.list.latency')
        end
      end

      context 'on failure' do
        before do
          allow(service).to receive(:invoice_service).and_raise(StandardError.new('API error'))
        end

        it 'increments initiated metric' do
          expect do
            service.list(count: 10, page: 1)
          rescue
            nil
          end
            .to trigger_statsd_increment('api.mcp.lighthouse.list.initiated')
        end

        it 'increments failure metric' do
          expect do
            service.list(count: 10, page: 1)
          rescue
            nil
          end
            .to trigger_statsd_increment('api.mcp.lighthouse.list.failure')
        end

        it 'does not increment success metric' do
          expect(StatsD).not_to receive(:increment).with('api.mcp.lighthouse.list.success')
          begin
            service.list(count: 10, page: 1)
          rescue
            nil
          end
        end
      end
    end

    describe '#get_detail' do
      let(:invoice_data) { { 'id' => 'invoice-1', 'account' => { 'reference' => 'Account/acc-1' } } }
      let(:mock_detail) { instance_double(Lighthouse::HCC::CopayDetail) }
      let(:base_stubs) do
        {
          invoice_service: double(read: invoice_data),
          fetch_invoice_dependencies: { account: {}, charge_items: {}, payments: [] },
          fetch_charge_item_dependencies: { encounters: {}, medication_dispenses: {} },
          fetch_medications: {}
        }
      end

      context 'on success' do
        before do
          allow(service).to receive_messages(base_stubs)
          allow(service).to receive_messages(
            retrieve_organization_address: {
              address_line1: '123 Test St',
              address_line2: nil,
              address_line3: nil,
              city: 'Tampa',
              state: 'FL',
              postalCode: '33601'
            },
            fetch_patient_data: {
              'resourceType' => 'Bundle',
              'entry' => [{ 'resource' => { 'resourceType' => 'Patient' } }]
            }
          )
          allow(Lighthouse::HCC::CopayDetail).to receive(:new).and_return(mock_detail)
        end

        it 'increments initiated metric' do
          allow(service).to receive(:invoices_for_organization).and_return([])
          expect { service.get_detail(id: 'invoice-1') }
            .to trigger_statsd_increment('api.mcp.lighthouse.detail.initiated')
        end

        it 'increments success metric' do
          allow(service).to receive(:invoices_for_organization).and_return([])
          expect { service.get_detail(id: 'invoice-1') }
            .to trigger_statsd_increment('api.mcp.lighthouse.detail.success')
        end

        it 'measures latency' do
          allow(service).to receive(:invoices_for_organization).and_return([])
          expect { service.get_detail(id: 'invoice-1') }
            .to trigger_statsd_measure('api.mcp.lighthouse.detail.latency')
        end
      end

      context 'when organization address is missing' do
        before do
          allow(service).to receive_messages(base_stubs)
          allow(service).to receive_messages(retrieve_organization_address: nil, fetch_patient_data: nil)
          allow(service).to receive(:invoices_for_organization).and_return([])
        end

        it 'still builds a CopayDetail with nil facility_address' do
          expect(Lighthouse::HCC::CopayDetail).to receive(:new).with(
            hash_including(facility_address: nil)
          ).and_return(mock_detail)
          service.get_detail(id: 'invoice-1')
        end
      end

      context 'when patient data is missing' do
        before do
          allow(service).to receive_messages(base_stubs)
          allow(service).to receive_messages(
            retrieve_organization_address: { city: 'Tampa' },
            fetch_patient_data: nil
          )

          allow(service).to receive(:invoices_for_organization).and_return([])
        end

        it 'still builds a CopayDetail with nil patient_data' do
          expect(Lighthouse::HCC::CopayDetail).to receive(:new).with(
            hash_including(patient_data: nil)
          ).and_return(mock_detail)
          service.get_detail(id: 'invoice-1')
        end
      end

      context 'when associated invoices are not requested' do
        before do
          allow(service).to receive_messages(base_stubs)
          allow(service).to receive_messages(retrieve_organization_address: nil, fetch_patient_data: nil)
          allow(service).to receive(:invoices_for_organization).and_return([])
          allow(Lighthouse::HCC::CopayDetail).to receive(:new).and_return(mock_detail)
        end

        it 'skips the organization invoice sweep' do
          service.get_detail(id: 'invoice-1', include_associated: false)

          expect(service).not_to have_received(:invoices_for_organization)
        end

        it 'builds the detail with no associated statements' do
          expect(Lighthouse::HCC::CopayDetail).to receive(:new).with(
            hash_including(associated_statements: [])
          ).and_return(mock_detail)

          service.get_detail(id: 'invoice-1', include_associated: false)
        end

        it 'still sweeps them when the caller does not opt out' do
          service.get_detail(id: 'invoice-1')

          expect(service).to have_received(:invoices_for_organization)
        end
      end

      context 'when associated invoices are requested by default' do
        let(:associated) { [{ 'resource' => { 'id' => 'assoc-1' } }] }

        before do
          allow(service).to receive_messages(base_stubs)
          allow(service).to receive_messages(retrieve_organization_address: nil, fetch_patient_data: nil)
          allow(service).to receive(:invoices_for_organization).and_return(associated)
        end

        it 'passes the swept invoices through to the detail' do
          expect(Lighthouse::HCC::CopayDetail).to receive(:new).with(
            hash_including(associated_statements: associated)
          ).and_return(mock_detail)

          service.get_detail(id: 'invoice-1')
        end

        it 'sweeps the invoice organization for the six month window' do
          allow(Lighthouse::HCC::CopayDetail).to receive(:new).and_return(mock_detail)

          service.get_detail(id: 'invoice-1')

          expect(service).to have_received(:invoices_for_organization).with(
            described_class::DEFAULT_MONTH_COUNT, described_class::DEFAULT_INVOICE_COUNT, nil, 'invoice-1'
          )
        end
      end

      context 'on failure' do
        before do
          allow(service).to receive(:invoice_service).and_raise(StandardError.new('API error'))
        end

        it 'increments initiated metric' do
          expect do
            service.get_detail(id: 'invoice-1')
          rescue
            nil
          end
            .to trigger_statsd_increment('api.mcp.lighthouse.detail.initiated')
        end

        it 'increments failure metric' do
          expect do
            service.get_detail(id: 'invoice-1')
          rescue
            nil
          end
            .to trigger_statsd_increment('api.mcp.lighthouse.detail.failure')
        end

        it 'does not increment success metric' do
          expect(StatsD).not_to receive(:increment).with('api.mcp.lighthouse.detail.success')
          begin
            service.get_detail(id: 'invoice-1')
          rescue
            nil
          end
        end
      end
    end
  end

  describe '#list' do
    it 'returns a list of invoices' do
      VCR.use_cassette('lighthouse/hcc/invoice_list_success') do
        allow(Auth::ClientCredentials::JWTGenerator).to receive(:generate_token).and_return('fake-jwt')

        service = MedicalCopays::LighthouseIntegration::Service.new('123')

        # Mock account data to avoid MissingAccountError
        allow(service).to receive(:fetch_accounts_for_invoices).and_return(mock_accounts)

        # TODO: Remove client-side filter testing once Lighthouse HCCC honors the
        # `status` FHIR search parameter. Then test the FHIR search parameter directly.
        # Currently the sandbox silently ignores it and returns unfiltered results.
        response = service.list(count: 10, page: 1)

        expect(response.total).to eq(10)
        expect(response.entries.first.class).to eq(Lighthouse::HCC::Invoice)
        expect(response.links.keys).to eq(%i[self first last])
        expect(response.page).to eq(1)
        expect(response.meta).to eq(
          {
            total: 10,
            page: 1,
            per_page: 10,
            copay_summary: {
              total_current_balance: 757.27,
              copay_bill_count: 10,
              last_updated_on: '2025-08-29T00:00:00Z'
            }
          }
        )
      end
    end

    it 'handles no records' do
      VCR.use_cassette('lighthouse/hcc/no_records', match_requests_on: %i[method path query]) do
        allow(Auth::ClientCredentials::JWTGenerator).to receive(:generate_token).and_return('fake-jwt')

        service = MedicalCopays::LighthouseIntegration::Service.new('123')

        # Mock empty account data
        allow(service).to receive(:fetch_accounts_for_invoices).and_return({})

        response = service.list(count: 50, page: 1)

        expect(response.entries).to be_empty
        expect(response.page).to eq(1)
        expect(response.meta).to eq(
          {
            total: 0, page: 1, per_page: 50,
            copay_summary: {
              total_current_balance: 0.0,
              copay_bill_count: 0,
              last_updated_on: nil
            }
          }
        )
      end
    end

    context 'Errors' do
      let(:service) { MedicalCopays::LighthouseIntegration::Service.new('123') }
      let(:raw_invoices) do
        {
          'entry' => [{
            'resource' => {
              'issuer' => { 'reference' => 'Organization/4-O3d8XK44ejMS' },
              'account' => { 'reference' => 'Account/account-123' }
            }
          }]
        }
      end

      it 'raises BadRequest for a 400 from Lighthouse' do
        VCR.use_cassette('lighthouse/hcc/auth_error') do
          allow(Auth::ClientCredentials::JWTGenerator)
            .to receive(:generate_token).and_return('fake-jwt')

          expect do
            service.list(count: 10, page: 1)
          end.to raise_error(Common::Exceptions::BadRequest)
        end
      end

      it 'raises MissingOrganizationRefError' do
        raw_invoices_with_nil_issuer = raw_invoices.deep_dup
        raw_invoices_with_nil_issuer['entry'].first['resource']['issuer']['reference'] = nil

        allow(service).to receive_messages(
          invoice_service: double(list: raw_invoices_with_nil_issuer),
          fetch_accounts_for_invoices: mock_accounts
        )

        expect { service.list(count: 10, page: 1) }
          .to raise_error(
            MedicalCopays::LighthouseIntegration::Exceptions::MissingOrganizationRefError,
            'No organization reference found'
          )
      end

      it 'raises MissingCityError' do
        allow(service).to receive_messages(
          invoice_service: double(list: raw_invoices),
          fetch_accounts_for_invoices: mock_accounts
        )
        allow(service).to receive(:retrieve_organization_address).with('4-O3d8XK44ejMS').and_return(nil)

        expect { service.list(count: 10, page: 1) }
          .to raise_error(
            MedicalCopays::LighthouseIntegration::Exceptions::MissingCityError,
            'Missing city for org_id 4-O3d8XK44ejMS'
          )
      end

      it 'raises MissingAccountError when account reference exists but account_data is nil' do
        allow(service).to receive_messages(
          invoice_service: double(list: raw_invoices),
          retrieve_organization_address: { city: 'Tampa' }
        )
        # Mock fetch_accounts_for_invoices to return empty hash (account_data is nil)
        allow(service).to receive(:fetch_accounts_for_invoices).and_return({})

        expect { service.list(count: 10, page: 1) }
          .to raise_error(
            MedicalCopays::LighthouseIntegration::Exceptions::MissingAccountError,
            'Missing account data for account_id account-123'
          )
      end

      it 'raises MissingAccountError when account reference is nil (account_id is nil)' do
        invoice_without_account = raw_invoices.deep_dup
        invoice_without_account['entry'].first['resource']['account'] = nil

        allow(service).to receive_messages(
          invoice_service: double(list: invoice_without_account),
          retrieve_organization_address: { city: 'Tampa' }
        )

        expect { service.list(count: 10, page: 1) }
          .to raise_error(
            MedicalCopays::LighthouseIntegration::Exceptions::MissingAccountError,
            'Missing account data for account_id '
          )
      end
    end
  end

  describe '#list_months' do
    # Callers rescue on the class that reaches them, so pin what an upstream failure
    # actually raises rather than trusting a hand-raised double.
    it 'lets the mapped Common::Exceptions error through when Lighthouse 500s' do
      allow(Auth::ClientCredentials::JWTGenerator).to receive(:generate_token).and_return('fake-jwt')
      stub_request(:post, %r{/oauth2/health-care-costs-coverage/system/v1/token})
        .to_return(status: 200, body: { access_token: 'fake-token', expires_in: 300 }.to_json,
                   headers: { 'Content-Type' => 'application/json' })
      stub_request(:get, %r{/services/health-care-costs-coverage/v0/r4/Invoice})
        .to_return(status: 500, body: '{}', headers: { 'Content-Type' => 'application/json' })

      expect { described_class.new('123').list_months }
        .to raise_error(Common::Exceptions::ExternalServerInternalServerError)
    end

    it 'declares an optional include_line_items keyword defaulting to false' do
      params = described_class.instance_method(:list_months).parameters
      expect(params).to include(%i[key include_line_items])
    end

    it 'does not call add_line_items_to_invoices! when include_line_items is omitted (default false)' do
      service = described_class.new('123')
      entry = {
        'resource' => {
          'id' => 'inv-1',
          'date' => Time.current.utc.iso8601,
          'issuer' => { 'reference' => 'Organization/org-1' }
        }
      }
      expect(service).not_to receive(:add_line_items_to_invoices!)
      collect_stub = {
        'raw_bundle' => { 'entry' => [entry], 'link' => [], 'total' => 1 },
        'entries' => [entry]
      }
      allow(service).to receive_messages(collect_invoices_in_range: collect_stub, build_invoice_entries: [])
      allow(Lighthouse::HCC::Bundle).to receive(:new).and_return(instance_double(Lighthouse::HCC::Bundle, entries: []))

      service.list_months
    end

    it 'attaches charge_items and built line_items from paged ChargeItem search when include_line_items is true' do
      service = described_class.new('123456789V123456')
      entry = {
        'resource' => {
          'id' => 'inv-1',
          'date' => Time.current.utc.iso8601,
          'issuer' => { 'reference' => 'Organization/org-1' },
          'identifier' => [{ 'type' => { 'text' => 'Bill Number' }, 'value' => 'BN-001' }],
          'lineItem' => [
            {
              'chargeItemReference' => { 'reference' => 'ChargeItem/ci-1' },
              'priceComponent' => [{ 'type' => 'base', 'amount' => { 'value' => 5.0 } }]
            },
            {
              'chargeItemReference' => { 'reference' => 'ChargeItem/ci-2' },
              'priceComponent' => [{ 'type' => 'base', 'amount' => { 'value' => 12.0 } }]
            }
          ]
        }
      }
      charge_item_rows = {
        'ci-1' => { 'id' => 'ci-1', 'status' => 'billable', 'occurrenceDateTime' => '2025-01-01T00:00:00Z' },
        'ci-2' => { 'id' => 'ci-2', 'status' => 'billable', 'occurrenceDateTime' => '2025-06-01T00:00:00Z' }
      }
      paginated_charge_items = instance_double(MedicalCopays::LighthouseIntegration::PaginatedService::ChargeItemService)
      allow(MedicalCopays::LighthouseIntegration::PaginatedService::ChargeItemService).to receive(:new)
        .with('123456789V123456').and_return(paginated_charge_items)
      allow(paginated_charge_items).to receive(:fetch_paginated_charge_items)
        .with(%w[ci-1 ci-2]).and_return(charge_item_rows)
      collect_stub = {
        'raw_bundle' => { 'entry' => [entry], 'link' => [], 'total' => 1 },
        'entries' => [entry]
      }
      allow(service).to receive_messages(collect_invoices_in_range: collect_stub, build_invoice_entries: [])
      allow(Lighthouse::HCC::Bundle).to receive(:new).and_return(instance_double(Lighthouse::HCC::Bundle, entries: []))

      service.list_months(include_line_items: true)

      expect(entry.dig('resource', 'charge_items')).to eq(charge_item_rows)
      expect(entry.dig('resource', 'line_items')).to contain_exactly(
        hash_including(billing_reference: 'ci-1', bill_number: 'BN-001',
                       price_components: array_including(hash_including(amount: 5.0))),
        hash_including(billing_reference: 'ci-2', bill_number: 'BN-001',
                       price_components: array_including(hash_including(amount: 12.0)))
      )
    end

    it 'omits bill_number from line_items when no Bill Number identifier is present' do
      service = described_class.new('123456789V123456')
      entry = {
        'resource' => {
          'id' => 'inv-1',
          'date' => Time.current.utc.iso8601,
          'issuer' => { 'reference' => 'Organization/org-1' },
          'lineItem' => [
            {
              'chargeItemReference' => { 'reference' => 'ChargeItem/ci-1' },
              'priceComponent' => [{ 'type' => 'base', 'amount' => { 'value' => 5.0 } }]
            }
          ]
        }
      }
      charge_item_rows = {
        'ci-1' => { 'id' => 'ci-1', 'status' => 'billable', 'occurrenceDateTime' => '2025-01-01T00:00:00Z' }
      }
      paginated_charge_items = instance_double(MedicalCopays::LighthouseIntegration::PaginatedService::ChargeItemService)
      allow(MedicalCopays::LighthouseIntegration::PaginatedService::ChargeItemService).to receive(:new)
        .with('123456789V123456').and_return(paginated_charge_items)
      allow(paginated_charge_items).to receive(:fetch_paginated_charge_items)
        .with(%w[ci-1]).and_return(charge_item_rows)
      collect_stub = {
        'raw_bundle' => { 'entry' => [entry], 'link' => [], 'total' => 1 },
        'entries' => [entry]
      }
      allow(service).to receive_messages(collect_invoices_in_range: collect_stub, build_invoice_entries: [])
      allow(Lighthouse::HCC::Bundle).to receive(:new).and_return(instance_double(Lighthouse::HCC::Bundle, entries: []))

      service.list_months(include_line_items: true)

      expect(entry.dig('resource', 'line_items')).to contain_exactly(
        hash_including(billing_reference: 'ci-1')
      )
      expect(entry.dig('resource', 'line_items', 0)).not_to have_key(:bill_number)
    end

    it 'returns invoices from the last 6 months' do
      Timecop.freeze(Time.zone.parse('2025-09-01')) do
        VCR.use_cassette('lighthouse/hcc/copay_list_by_month', match_requests_on: %i[method path query]) do
          allow(Auth::ClientCredentials::JWTGenerator).to receive(:generate_token).and_return('fake-jwt')

          service = MedicalCopays::LighthouseIntegration::Service.new('123')

          allow(service).to receive(:fetch_accounts_for_invoices).and_return(mock_accounts)

          # Default include_line_items: false — Invoice cassette only.
          response = service.list_months

          from = 6.months.ago.utc

          response.entries.each do |invoice|
            date = Time.iso8601(invoice.instance_variable_get(:@params).dig('resource', 'date'))
            expect(date).to be >= from
          end
        end
      end
    end
  end

  describe '#get_detail' do
    it 'returns copay detail with populated attributes' do
      VCR.use_cassette('lighthouse/hcc/copay_detail_success') do
        allow(Auth::ClientCredentials::JWTGenerator)
          .to receive(:generate_token).and_return('fake-jwt')

        service = MedicalCopays::LighthouseIntegration::Service.new('32000551')
        allow(service).to receive(:invoices_for_organization).and_return([])
        result = service.get_detail(id: '4-1abZUKu7LnbcQc')

        expect(result).to be_a(Lighthouse::HCC::CopayDetail)
        expect(result.external_id).to be_present
        expect(result.facility).to be_present
        expect(result.facility).to be_a(Hash)
        expect(result.facility['name']).to be_present
        expect(result.facility['address']).to be_a(Hash)

        address = result.facility['address']
        expect(address['address_line1']).to eq('3000 CORAL HILLS DR')
        expect(address['city']).to eq('CORAL SPRINGS')
        expect(address['state']).to eq('FL')
        expect(address['postalCode']).to eq('330654108')

        expect(result.status).to be_present
        expect(result.line_items).to be_an(Array)
        expect(result.payments).to be_an(Array)
      end
    end

    it 'raises BadRequest for a 400 from Lighthouse' do
      VCR.use_cassette('lighthouse/hcc/auth_error') do
        allow(Auth::ClientCredentials::JWTGenerator)
          .to receive(:generate_token).and_return('fake-jwt')

        service = MedicalCopays::LighthouseIntegration::Service.new('32000551')

        expect do
          service.get_detail(id: '4-1abZUKu7LnbcQc')
        end.to raise_error(Common::Exceptions::BadRequest)
      end
    end
  end

  describe '#summary' do
    let(:icn) { '123' }
    let(:service) { described_class.new(icn) }
    let(:invoice_service) { instance_double(Lighthouse::HealthcareCostAndCoverage::Invoice::Service) }

    before do
      allow(service).to receive(:invoice_service).and_return(invoice_service)
    end

    def invoice_entry(date:, balance:, status: nil)
      entry = {
        'resource' => {
          'date' => date,
          'totalPriceComponent' => [
            {
              'type' => 'base',
              'amount' => { 'value' => balance }
            },
            {
              'type' => 'informational',
              'code' => { 'text' => 'Original Amount' },
              'amount' => { 'value' => balance }
            }
          ]
        }
      }
      entry['resource']['status'] = status if status
      entry
    end

    it 'aggregates total amount and count within the month window' do
      now = Time.current.utc

      entries = [
        invoice_entry(date: now.iso8601, balance: 10.50),
        invoice_entry(date: now.iso8601, balance: 20.25)
      ]

      allow(invoice_service).to receive(:list)
        .with(count: 50, page: 1)
        .and_return({ 'entry' => entries })

      allow(invoice_service).to receive(:list)
        .with(count: 50, page: 2)
        .and_return({ 'entry' => [] })

      result = service.summary(month_count: 6)

      expect(result).to eq(
        entries: [],
        meta: {
          total_amount_due: 30.75,
          total_copays: 2,
          month_window: 6
        }
      )
    end

    it 'stops processing when an invoice is older than the window' do
      recent = Time.current.utc
      old = 7.months.ago.utc

      entries = [
        invoice_entry(date: recent.iso8601, balance: 15.00),
        invoice_entry(date: old.iso8601, balance: 999.99)
      ]

      allow(invoice_service).to receive(:list)
        .with(count: 50, page: 1)
        .and_return({ 'entry' => entries })

      allow(invoice_service).to receive(:list)
        .with(count: 50, page: 2)
        .and_return({ 'entry' => [] })

      result = service.summary(month_count: 6)

      expect(result[:meta][:total_amount_due]).to eq(15.0)
      expect(result[:meta][:total_copays]).to eq(1)
    end

    it 'skips entries without a date' do
      entries = [
        { 'resource' => {} },
        invoice_entry(date: Time.current.utc.iso8601, balance: 12.00)
      ]

      allow(invoice_service).to receive(:list)
        .with(count: 50, page: 1)
        .and_return({ 'entry' => entries })

      allow(invoice_service).to receive(:list)
        .with(count: 50, page: 2)
        .and_return({ 'entry' => [] })

      result = service.summary

      expect(result[:meta][:total_amount_due]).to eq(12.0)
      expect(result[:meta][:total_copays]).to eq(1)
    end

    it 'returns zero totals when no entries are returned' do
      allow(invoice_service).to receive(:list)
        .with(count: 50, page: 1)
        .and_return({ 'entry' => [] })

      result = service.summary

      expect(result).to eq(
        entries: [],
        meta: {
          total_amount_due: 0.0,
          total_copays: 0,
          month_window: 6
        }
      )
    end

    context 'with status filter' do
      it 'filters summary by status from unfiltered data' do
        unfiltered_entries = [
          invoice_entry(date: Time.current.utc.iso8601, balance: 10.50, status: 'issued'),
          invoice_entry(date: Time.current.utc.iso8601, balance: 20.25, status: 'balanced'),
          invoice_entry(date: Time.current.utc.iso8601, balance: 30.00, status: 'draft'),
          invoice_entry(date: Time.current.utc.iso8601, balance: 15.00, status: 'cancelled')
        ]

        # Lighthouse API call where status isn't applied as a search param yet, so everything will get returned.
        allow(invoice_service).to receive(:list)
          .with(count: 50, page: 1, status: 'issued,balanced')
          .and_return({ 'entry' => unfiltered_entries })

        result = service.summary(month_count: 6, status: 'issued,balanced')

        # Service should have filtered to only issued and balanced
        expect(result[:meta][:total_amount_due]).to eq(30.75)
        expect(result[:meta][:total_copays]).to eq(2)
      end

      it 'returns zero totals when no entries match status filter' do
        unfiltered_entries = [
          invoice_entry(date: Time.current.utc.iso8601, balance: 10.50, status: 'draft'),
          invoice_entry(date: Time.current.utc.iso8601, balance: 20.25, status: 'cancelled')
        ]

        allow(invoice_service).to receive(:list)
          .with(count: 50, page: 1, status: 'issued')
          .and_return({ 'entry' => unfiltered_entries })

        result = service.summary(month_count: 6, status: 'issued')

        expect(result[:meta][:total_amount_due]).to eq(0.0)
        expect(result[:meta][:total_copays]).to eq(0)
      end
    end
  end

  describe '#fetch_charge_items' do
    let(:icn) { '123456789V123456' }
    let(:service) { described_class.new(icn) }
    let(:charge_item_client) { instance_double(Lighthouse::HealthcareCostAndCoverage::ChargeItem::Service) }

    let(:hccc_charge_item) { Lighthouse::HealthcareCostAndCoverage::ChargeItem::Service }

    before do
      allow(hccc_charge_item).to receive(:new).with(icn).and_return(charge_item_client)
    end

    it 'returns an empty hash when ids are empty' do
      expect(service.send(:fetch_charge_items, {})).to eq({})
      expect(hccc_charge_item).not_to have_received(:new)
    end

    it 'calls Lighthouse once with count and keeps only ChargeItems referenced by line items' do
      invoice_data = {
        'lineItem' => [
          { 'chargeItemReference' => { 'reference' => 'ChargeItem/want-this' } }
        ]
      }

      allow(charge_item_client).to receive(:list).with(count: described_class::CHARGE_ITEM_FETCH_LIMIT).and_return(
        'entry' => [
          { 'resource' => { 'id' => 'want-this', 'status' => 'billable' } },
          { 'resource' => { 'id' => 'other', 'status' => 'billable' } }
        ]
      )

      result = service.send(:fetch_charge_items, invoice_data)

      expect(result.keys).to contain_exactly('want-this')
      expect(result['want-this']['status']).to eq('billable')
      expect(charge_item_client).to have_received(:list).with(count: described_class::CHARGE_ITEM_FETCH_LIMIT).once
    end

    it 'collects distinct ChargeItems when an invoice has multiple line items (one reference per line item)' do
      invoice_data = {
        'lineItem' => [
          { 'chargeItemReference' => { 'reference' => 'ChargeItem/ci-1' } },
          { 'chargeItemReference' => { 'reference' => 'ChargeItem/ci-2' } }
        ]
      }

      allow(charge_item_client).to receive(:list).with(count: described_class::CHARGE_ITEM_FETCH_LIMIT).and_return(
        'entry' => [
          { 'resource' => { 'id' => 'ci-1', 'status' => 'billable' } },
          { 'resource' => { 'id' => 'ci-2', 'status' => 'billed' } },
          { 'resource' => { 'id' => 'not-on-invoice', 'status' => 'billable' } }
        ]
      )

      result = service.send(:fetch_charge_items, invoice_data)

      expect(result.keys).to contain_exactly('ci-1', 'ci-2')
      expect(result['ci-1']['status']).to eq('billable')
      expect(result['ci-2']['status']).to eq('billed')
    end

    it 'ignores bundle entries without a resource id' do
      invoice_data = {
        'lineItem' => [
          { 'chargeItemReference' => { 'reference' => 'ChargeItem/ci-1' } }
        ]
      }

      allow(charge_item_client).to receive(:list).with(count: described_class::CHARGE_ITEM_FETCH_LIMIT).and_return(
        'entry' => [
          { 'resource' => { 'status' => 'billable' } },
          { 'resource' => { 'id' => 'ci-1', 'status' => 'billable' } }
        ]
      )

      result = service.send(:fetch_charge_items, invoice_data)

      expect(result.keys).to eq(['ci-1'])
    end

    it 'returns an empty hash when the ChargeItem list raises' do
      invoice_data = {
        'lineItem' => [
          { 'chargeItemReference' => { 'reference' => 'ChargeItem/x' } }
        ]
      }

      allow(charge_item_client).to receive(:list).and_raise(StandardError.new('API error'))
      allow(Rails.logger).to receive(:warn)

      expect(service.send(:fetch_charge_items, invoice_data)).to eq({})
    end
  end

  describe '#entry_has_vista_status?' do
    let(:service) { described_class.new('123456789V123456') }

    def entry_with_vista_status(status)
      { 'resource' => { '_status' => { 'valueCodeableConcept' => { 'text' => status } } } }
    end

    it 'returns true when the VistA status text matches' do
      expect(service.send(:entry_has_vista_status?, entry_with_vista_status('ACTIVE'), 'ACTIVE')).to be true
    end

    it 'returns false when the VistA status text does not match' do
      expect(service.send(:entry_has_vista_status?, entry_with_vista_status('INACTIVE'), 'ACTIVE')).to be false
    end

    it 'returns false when the _status extension is absent' do
      expect(service.send(:entry_has_vista_status?, {}, 'ACTIVE')).to be false
    end

    it 'is case-sensitive' do
      expect(service.send(:entry_has_vista_status?, entry_with_vista_status('active'), 'ACTIVE')).to be false
    end
  end

  describe '#parse_status_filter' do
    let(:service) { described_class.new('123456789V123456') }

    it 'returns nil when status is blank' do
      expect(service.send(:parse_status_filter, nil)).to be_nil
      expect(service.send(:parse_status_filter, '')).to be_nil
    end

    it 'returns allowed statuses when valid statuses are provided' do
      result = service.send(:parse_status_filter, 'issued,balanced')
      expect(result).to eq(%w[issued balanced])
    end

    it 'filters out invalid statuses' do
      result = service.send(:parse_status_filter, 'issued,invalid,balanced')
      expect(result).to eq(%w[issued balanced])
    end

    it 'returns empty array when no valid statuses match' do
      result = service.send(:parse_status_filter, 'invalid1,invalid2')
      expect(result).to eq([])
    end

    it 'handles whitespace in status values' do
      result = service.send(:parse_status_filter, ' issued , balanced ')
      expect(result).to eq(%w[issued balanced])
    end
  end

  describe '#apply_status_filter!' do
    let(:service) { described_class.new('123456789V123456') }
    let(:bundle) do
      {
        'entry' => [
          { 'resource' => { 'status' => 'issued' } },
          { 'resource' => { 'status' => 'balanced' } },
          { 'resource' => { 'status' => 'draft' } }
        ],
        'total' => 3
      }
    end

    it 'filters entries by status' do
      service.send(:apply_status_filter!, bundle, %w[issued balanced])

      expect(bundle['entry'].length).to eq(2)
      expect(bundle['entry'].map { |e| e['resource']['status'] }).to eq(%w[issued balanced])
      expect(bundle['total']).to eq(2)
    end

    it 'returns bundle unchanged when statuses is nil' do
      original_bundle = bundle.dup
      service.send(:apply_status_filter!, bundle, nil)

      expect(bundle).to eq(original_bundle)
    end

    it 'handles empty entry array' do
      bundle['entry'] = []
      bundle['total'] = 0

      service.send(:apply_status_filter!, bundle, %w[issued])

      expect(bundle['entry']).to be_empty
      expect(bundle['total']).to eq(0)
    end

    context "when statuses include 'active'" do
      def entry_with_status(id, fhir_status, vista_status = nil)
        entry = { 'id' => id, 'resource' => { 'status' => fhir_status } }
        entry['resource']['_status'] = { 'valueCodeableConcept' => { 'text' => vista_status } } if vista_status
        entry
      end

      let(:bundle) do
        {
          'entry' => [
            entry_with_status('issued-active', 'issued', 'ACTIVE'),
            entry_with_status('balanced-inactive', 'balanced'),
            entry_with_status('balanced-active', 'balanced', 'ACTIVE'),
            entry_with_status('draft-inactive', 'draft'),
            entry_with_status('draft-active', 'draft', 'ACTIVE')
          ],
          'total' => 5
        }
      end

      it 'includes entries with resource status of balanced or issued' do
        service.send(:apply_status_filter!, bundle, %w[active])

        returned_entry_ids = bundle['entry'].map { |e| e['id'] }
        expect(returned_entry_ids).to include('issued-active', 'balanced-active')
      end

      it 'excludes entries with resource status of balanced or issued but not VistA ACTIVE' do
        service.send(:apply_status_filter!, bundle, %w[active])

        returned_entry_ids = bundle['entry'].map { |e| e['id'] }
        expect(returned_entry_ids).not_to include('balanced-inactive')
      end

      it 'excludes entries that are neither balanced/issued nor VistA ACTIVE' do
        service.send(:apply_status_filter!, bundle, %w[active])

        returned_entry_ids = bundle['entry'].map { |e| e['id'] }
        expect(returned_entry_ids).not_to include('draft-inactive', 'draft-active')
      end

      it 'updates the total to match the filtered entry count' do
        service.send(:apply_status_filter!, bundle, %w[active])

        expect(bundle['total']).to eq(2)
      end
    end
  end

  describe '#invoices_for_organization' do
    let(:service) { described_class.new('123456789V123456') }
    let(:organization_id) { 'org-test' }
    let(:current_invoice_id) { 'invoice-open' }

    let(:associated_invoice_entry) do
      {
        'resource' => {
          'id' => 'invoice-associated',
          'date' => '2025-03-01T12:00:00Z',
          'issuer' => { 'reference' => "Organization/#{organization_id}" },
          'lineItem' => [
            {
              'chargeItemReference' => {
                'reference' => 'https://sandbox.fhir/r4/ChargeItem/ci-fhir-id'
              },
              'priceComponent' => [{ 'type' => 'base', 'amount' => { 'value' => 50.0 } }]
            }
          ]
        }
      }
    end

    let(:charge_item_resource) do
      {
        'id' => 'ci-fhir-id',
        'status' => 'billed',
        'code' => { 'text' => 'OUTPATIENT CARE' },
        'enteredDate' => '2025-05-14T15:00:00Z'
      }
    end

    before do
      allow(service).to receive_messages(collect_invoices_in_range:
        { 'entries' => [associated_invoice_entry],
          'raw_bundle' => {} }, fetch_charge_items: { 'ci-fhir-id' => charge_item_resource })
    end

    it 'stores mapped charge_items and raw _associated_charge_items on each org invoice resource' do
      results = service.send(
        :invoices_for_organization,
        described_class::DEFAULT_MONTH_COUNT,
        described_class::DEFAULT_INVOICE_COUNT,
        organization_id,
        current_invoice_id
      )

      resource = results.first['resource']

      expect(resource['_associated_charge_items']).to eq(
        'ci-fhir-id' => charge_item_resource
      )

      expect(resource['charge_items']).to contain_exactly(
        a_hash_including(
          id: 'ci-fhir-id',
          status: 'billed',
          code: 'OUTPATIENT CARE',
          entered_date: '2025-05-14T15:00:00Z'
        )
      )
    end
  end

  describe '#collect_invoices_in_range' do
    let(:service) { described_class.new('123456789V123456') }
    let(:invoice_svc) { instance_double(Lighthouse::HealthcareCostAndCoverage::Invoice::Service) }
    let(:now) { Time.current.utc }

    before do
      allow(service).to receive(:invoice_service).and_return(invoice_svc)
    end

    def range_entry(fhir_status, vista_status: nil)
      entry = { 'resource' => { 'date' => now.iso8601, 'status' => fhir_status } }
      entry['resource']['_status'] = { 'valueCodeableConcept' => { 'text' => vista_status } } if vista_status
      entry
    end

    context "when status is 'active'" do
      let(:entries) do
        [
          range_entry('balanced'),
          range_entry('balanced', vista_status: 'ACTIVE'),
          range_entry('issued'),
          range_entry('issued', vista_status: 'ACTIVE'),
          range_entry('draft', vista_status: 'ACTIVE'),
          range_entry('cancelled'),
          range_entry('draft')
        ]
      end

      before do
        allow(invoice_svc).to receive(:list)
          .with(count: 50, page: 1, status: 'active')
          .and_return({ 'entry' => entries })
      end

      it 'collects entries with a FHIR status of balanced or issued and VistA ACTIVE' do
        result = service.send(:collect_invoices_in_range, 7, status: 'active')

        collected_statuses = result['entries'].map { |e| e.dig('resource', 'status') }
        expect(collected_statuses).to include('balanced', 'issued')
        collected_vista_statuses = result['entries'].map do |e|
          e.dig('resource', '_status', 'valueCodeableConcept', 'text')
        end
        expect(collected_vista_statuses).to all(eq('ACTIVE'))
      end

      it 'excludes entries that are neither balanced/issued nor VistA ACTIVE' do
        result = service.send(:collect_invoices_in_range, 6, status: 'active')

        expect(result['entries'].length).to eq(2)
        collected_statuses = result['entries'].map { |e| e.dig('resource', 'status') }
        expect(collected_statuses).not_to include('cancelled')
      end
    end
  end
end
