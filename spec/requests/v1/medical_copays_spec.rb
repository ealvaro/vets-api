# frozen_string_literal: true

require 'rails_helper'
require 'lighthouse/healthcare_cost_and_coverage/configuration'
require 'medical_copays/cerner_facilities'

RSpec.describe 'V1::MedicalCopays', type: :request do
  include ActiveSupport::Testing::TimeHelpers
  let(:current_user) { build(:user, :loa3, icn: '123') }

  before do
    sign_in_as(current_user)

    allow(Rails.logger).to receive(:warn)
    allow_any_instance_of(Auth::ClientCredentials::Service).to receive(:get_token).and_return('fake-access-token')
    allow(Flipper).to receive(:enabled?).with(:cerner_user_override_lighthouse_copays).and_return(false)
    allow(Flipper).to receive(:enabled?).with(:vha_show_payment_history, anything).and_return(false)
  end

  describe 'index' do
    before do
      sign_in_as(current_user)

      allow_any_instance_of(Auth::ClientCredentials::Service).to receive(:get_token).and_return('fake-access-token')

      # Default all feature flags to false; individual examples override specific flags below.
      allow(Flipper).to receive(:enabled?).and_return(false)
      allow(Flipper).to receive(:enabled?).with(:cerner_user_override_lighthouse_copays).and_return(false)
      allow(Flipper).to receive(:enabled?).with(:vha_show_payment_history, anything).and_return(false)
    end

    context 'vha_show_payment_history flag enabled' do
      before do
        allow(Flipper).to receive(:enabled?).with(:vha_show_payment_history, anything).and_return(true)
        allow(MedicalCopays::CernerFacilities).to receive(:cerner_copay_user?).and_return(false)
      end

      it 'returns a formatted hash response' do
        travel_to Time.utc(2025, 8, 1) do
          VCR.use_cassette('lighthouse/hcc/copay_list_by_month', match_requests_on: %i[method path query]) do
            # Mock account data to avoid MissingAccountError
            allow_any_instance_of(MedicalCopays::LighthouseIntegration::Service)
              .to receive(:fetch_accounts_for_invoices)
              .and_return(
                {
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
              )

            get '/v1/medical_copays'

            response_body = JSON.parse(response.body)
            meta = response_body['meta']
            copay_summary = meta['copay_summary']
            data_element = response_body['data'].first

            expect(copay_summary.keys)
              .to eq(%w[total_current_balance copay_bill_count last_updated_on])

            expect(meta.keys)
              .to eq(%w[total page per_page copay_summary])
            expect(data_element['attributes'].keys)
              .to match_array(
                %w[
                  url
                  facility
                  facilityId
                  lastUpdatedAt
                  city
                  externalId
                  latestBillingRef
                  currentBalance
                  previousBalance
                  previousUnpaidBalance
                  invoiceDate
                  lineItems
                  statementGeneratedDay
                ]
              )
          end
        end
      end

      it 'handles auth error' do
        VCR.use_cassette('lighthouse/hcc/auth_error') do
          allow_any_instance_of(Auth::ClientCredentials::Service)
            .to receive(:get_token).and_call_original
          allow(Auth::ClientCredentials::JWTGenerator)
            .to receive(:generate_token).and_return('fake-jwt')

          get '/v1/medical_copays'

          response_body = JSON.parse(response.body)
          errors = response_body['errors']

          expect(errors.first.keys).to eq(%w[error error_description status code title detail])
        end
      end

      it 'handles no records returned' do
        VCR.use_cassette('lighthouse/hcc/no_records', match_requests_on: %i[method path query]) do
          allow(Auth::ClientCredentials::JWTGenerator).to receive(:generate_token).and_return('fake-jwt')
          get '/v1/medical_copays'

          response_body = JSON.parse(response.body)
          expect(response_body['data']).to eq([])
        end
      end
    end

    context 'cerner facility ids present' do
      let(:copays) { { data: [], status: 200 } }

      before do
        allow_any_instance_of(User).to receive(:cerner_facility_ids).and_return(['267MHV'])
      end

      it 'returns vbs response' do
        travel_to Time.utc(2025, 8, 1) do
          allow_any_instance_of(MedicalCopays::VBS::Service).to receive(:get_copays).and_return(copays)

          get '/v1/medical_copays'

          response_body = JSON.parse(response.body)
          expect(response_body).to eq({ 'data' => [], 'status' => 200, 'isCerner' => true })
        end
      end
    end

    context 'include_line_items (Lighthouse index)' do
      let(:invoice_bundle) do
        instance_double(
          Lighthouse::HCC::Bundle,
          entries: [],
          links: {},
          meta: { total: 0, page: 1, per_page: 50,
                  copay_summary: { 'total_current_balance' => 0.0, 'copay_bill_count' => 0, 'last_updated_on' => nil } }
        )
      end

      before do
        allow(MedicalCopays::CernerFacilities).to receive(:cerner_copay_user?).and_return(false)
      end

      it 'passes include_line_items as nil when the param is omitted' do
        allow(Flipper).to receive(:enabled?).with(:vha_show_payment_history, anything).and_return(true)

        copay_service = instance_double(MedicalCopays::LighthouseIntegration::Service)
        allow(MedicalCopays::LighthouseIntegration::Service)
          .to receive(:new).with(current_user.icn).and_return(copay_service)
        allow(copay_service).to receive(:list_months).and_return(invoice_bundle)
        allow(Lighthouse::HCC::InvoiceSerializer).to receive(:new).and_return(
          double(serializable_hash: { 'data' => [], 'meta' => {} })
        )

        get '/v1/medical_copays'

        expect(copay_service).to have_received(:list_months).with(
          status: nil,
          include_line_items: nil
        )
      end

      it 'passes include_line_items through from params when provided' do
        allow(Flipper).to receive(:enabled?).with(:vha_show_payment_history, anything).and_return(true)

        copay_service = instance_double(MedicalCopays::LighthouseIntegration::Service)
        allow(MedicalCopays::LighthouseIntegration::Service)
          .to receive(:new).with(current_user.icn).and_return(copay_service)
        allow(copay_service).to receive(:list_months).and_return(invoice_bundle)
        allow(Lighthouse::HCC::InvoiceSerializer).to receive(:new).and_return(
          double(serializable_hash: { 'data' => [], 'meta' => {} })
        )

        get '/v1/medical_copays', params: { include_line_items: 'true', status: 'issued' }

        expect(copay_service).to have_received(:list_months).with(
          status: 'issued',
          include_line_items: 'true'
        )
      end
    end
  end

  describe 'show' do
    let(:current_user) { build(:user, :loa3, icn: '32000551') }

    # Service uses Concurrent::Promises for parallel API calls, so we need:
    # - allow_playback_repeats: concurrent threads may replay same response
    # - match_requests_on: [:method, :uri] to handle request ordering differences
    let(:vcr_options) { { allow_playback_repeats: true, match_requests_on: %i[method uri] } }

    it 'returns nil for unmatched identifiers' do
      VCR.use_cassette('lighthouse/hcc/copay_detail_success_no_identifiers', vcr_options) do
        travel_to Time.utc(2025, 6, 1) do
          allow(Flipper).to receive(:enabled?).with(:vha_show_payment_history).and_return(true)
          allow(Auth::ClientCredentials::JWTGenerator).to receive(:generate_token).and_return('fake-jwt')
          allow(MedicalCopays::CernerFacilities).to receive(:cerner_copay_user?).and_return(false)
          allow_any_instance_of(V1::MedicalCopaysController).to receive(:use_vbs?).and_return(false)
          # Mock account data to avoid MissingAccountError
          allow_any_instance_of(MedicalCopays::LighthouseIntegration::Service)
            .to receive(:fetch_accounts_for_invoices)
            .and_return(
              {
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
            )
          get '/v1/medical_copays/4-1abZUKu7LnbcQc'

          expect(response).to have_http_status(:ok)

          response_body = JSON.parse(response.body)
          data = response_body['data']

          expect(data['type']).to eq('medicalCopayDetails')
          expect(data['id']).to be_present
          expect(data['attributes']['billNumber']).to be_nil
          expect(data['attributes']['accountNumber']).to be_nil
          expect(Rails.logger).to have_received(:warn).with('Bill number not found in invoice/statement data')
          expect(Rails.logger).to have_received(:warn).with('Account number not found in account data')
        end
      end
    end

    it 'returns copay detail for authenticated user' do
      allow(Flipper).to receive(:enabled?).with(:vha_show_payment_history, anything).and_return(true)
      VCR.use_cassette('lighthouse/hcc/copay_detail_success', vcr_options) do
        # Use June so `collect_invoices_in_range` (6-month window) includes the Jan 2025
        # invoice; with Aug 1 that row falls just outside the window. Associated rows must
        # be older than the detail invoice (March 2025) per CopayDetail#sorted_invoices.
        travel_to Time.utc(2025, 6, 1) do
          allow(Auth::ClientCredentials::JWTGenerator).to receive(:generate_token).and_return('fake-jwt')
          allow(MedicalCopays::CernerFacilities).to receive(:cerner_copay_user?).and_return(false)
          allow_any_instance_of(V1::MedicalCopaysController).to receive(:use_vbs?).and_return(false)
          # Mock account data to avoid MissingAccountError
          allow_any_instance_of(MedicalCopays::LighthouseIntegration::Service)
            .to receive(:fetch_accounts_for_invoices)
            .and_return(
              {
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
            )

          get '/v1/medical_copays/4-1abZUKu7LnbcQc'

          expect(response).to have_http_status(:ok)

          response_body = JSON.parse(response.body)
          data = response_body['data']

          expect(data['type']).to eq('medicalCopayDetails')
          expect(data['id']).to be_present
          expect(data['attributes'].keys).to match_array(
            %w[
              externalId
              facility
              patient
              billNumber
              status
              statusDescription
              invoiceDate
              paymentDueDate
              accountNumber
              originalAmount
              principalBalance
              interestBalance
              administrativeCostBalance
              principalPaid
              interestPaid
              administrativeCostPaid
              lineItems
              payments
              associatedStatements
              associatedInvoices
              statementGeneratedDay
            ]
          )
          expect(data['meta'].keys).to match_array(%w[line_item_count payment_count])

          expect(data['attributes']['billNumber']).to eq('573-K3FDEC0')
          expect(data['attributes']['accountNumber']).to eq('5730000000038703KIRLI')

          facility = data['attributes']['facility']
          expect(facility).to be_a(Hash)
          expect(facility['name']).to be_present
          expect(facility['address']).to be_a(Hash)
          expect(data.dig('attributes', 'associatedStatements').pluck('id'))
            .to eq(%w[4-1abZUKu7LpqlAw 4-1abZUKu7LncAWg])
          expect(data.dig('attributes', 'associatedStatements').pluck('bill_number'))
            .to eq(%w[573-K3FE740 573-K3FEDF3])
          expect(data.dig('attributes', 'associatedInvoices').pluck('composite_id'))
            .to eq(%w[4-5pFm5Av0PHt-1-2025 4-5pFm5Av0PHt-12-2024])
          address = facility['address']
          expect(address['address_line1']).to eq('3000 CORAL HILLS DR')
          expect(address['city']).to eq('CORAL SPRINGS')
          expect(address['state']).to eq('FL')
          expect(address['postalCode']).to eq('330654108')

          patient = data['attributes']['patient']
          expect(patient).to be_a(Hash)
          expect(patient['first_name']).to eq('Ivory697')
          expect(patient['middle_name']).to be_nil
          expect(patient['last_name']).to eq('Kirlin939')
          expect(patient['address']).to be_a(Hash)
          expect(patient['address']['address_line1']).to eq('197 Ullrich Well')
          expect(patient['address']['city']).to eq('Broadview Park')
          expect(patient['address']['state']).to eq('FL')
          expect(patient['address']['postalCode']).to eq('00000')
        end
      end
    end

    it 'handles auth error' do
      allow(Flipper).to receive(:enabled?).with(:vha_show_payment_history, anything).and_return(true)
      VCR.use_cassette('lighthouse/hcc/auth_error', vcr_options) do
        allow(Auth::ClientCredentials::JWTGenerator).to receive(:generate_token).and_return('fake-jwt')
        allow(MedicalCopays::CernerFacilities).to receive(:cerner_copay_user?).and_return(false)
        allow_any_instance_of(V1::MedicalCopaysController).to receive(:use_vbs?).and_return(false)

        # Block the invoice GET (the unhandled request) without referencing Invoice::Service
        allow_any_instance_of(Lighthouse::HealthcareCostAndCoverage::Configuration)
          .to receive(:get)
          .and_raise(Common::Client::Errors::ClientError.new(nil, 400))

        get '/v1/medical_copays/4-1abZUKu7LnbcQc'

        body = JSON.parse(response.body)
        errors = body['errors']

        expect(errors.first.keys).to match_array(%w[title detail status code])
      end
    end

    it 'includes isCerner false for non-cerner user' do
      allow(Flipper).to receive(:enabled?).with(:vha_show_payment_history, anything).and_return(true)
      VCR.use_cassette('lighthouse/hcc/copay_detail_success', vcr_options) do
        allow(Auth::ClientCredentials::JWTGenerator).to receive(:generate_token).and_return('fake-jwt')
        allow(MedicalCopays::CernerFacilities).to receive(:cerner_copay_user?).and_return(false)
        allow_any_instance_of(V1::MedicalCopaysController).to receive(:use_vbs?).and_return(false)
        # Mock account data to avoid MissingAccountError
        allow_any_instance_of(MedicalCopays::LighthouseIntegration::Service)
          .to receive(:fetch_accounts_for_invoices)
          .and_return(
            {
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
          )

        get '/v1/medical_copays/4-1abZUKu7LnbcQc'

        expect(response).to have_http_status(:ok)
        response_body = JSON.parse(response.body)
        expect(response_body['isCerner']).to be false
      end
    end

    # Cerner users receive the VBS response shape (matching V0) rather than
    # the JSON:API structure used for Lighthouse responses above.
    context 'cerner user' do
      let(:copay_detail) { { data: { 'id' => 'abc-123', 'pSStatementVal' => 'test' }, status: 200 } }

      before do
        allow(MedicalCopays::CernerFacilities).to receive(:cerner_copay_user?).and_return(true)
      end

      it 'returns vbs response with isCerner true' do
        allow_any_instance_of(MedicalCopays::VBS::Service).to receive(:get_copay_by_id)
          .with('abc-123')
          .and_return(copay_detail)

        get '/v1/medical_copays/abc-123'

        expect(response).to have_http_status(:ok)
        response_body = JSON.parse(response.body)
        expect(response_body['isCerner']).to be true
        expect(response_body['data']['id']).to eq('abc-123')
      end

      it 'returns 404 when statement not found' do
        allow_any_instance_of(MedicalCopays::VBS::Service).to receive(:get_copay_by_id)
          .and_raise(MedicalCopays::VBS::Service::StatementNotFound)

        get '/v1/medical_copays/nonexistent-id'

        expect(response).to have_http_status(:not_found)
      end
    end
  end

  describe 'summary' do
    # Swagger: GET /v1/medical_copays/summary — JSON:API-shaped JSON, empty `data`, rollups in `meta`
    # (`total_amount_due`, `total_copays`, `month_window`); no `isCerner` (Lighthouse-only path).
    let(:service) { instance_double(MedicalCopays::LighthouseIntegration::Service) }
    let(:summary_meta) do
      {
        total_amount_due: 125.50,
        total_copays: 3,
        month_window: 6
      }
    end
    let(:summary_result) { { entries: [], meta: summary_meta } }

    before do
      allow(MedicalCopays::CernerFacilities).to receive(:cerner_copay_user?).and_return(false)
      allow_any_instance_of(V1::MedicalCopaysController).to receive(:use_vbs?).and_return(false)
      allow(MedicalCopays::LighthouseIntegration::Service)
        .to receive(:new)
        .with(current_user.icn)
        .and_return(service)
      allow(service).to receive(:summary).and_return(summary_result)
    end

    it 'returns 200 with swagger meta fields and empty data (default month window)' do
      get '/v1/medical_copays/summary'

      expect(service).to have_received(:summary).with(month_count: 6, status: nil)
      expect(response).to have_http_status(:ok)

      body = JSON.parse(response.body)

      expect(body['data']).to eq([])
      expect(body['meta'].keys)
        .to match_array(%w[total_amount_due total_copays month_window])
      expect(body['meta']).to eq(
        'total_amount_due' => 125.5,
        'total_copays' => 3,
        'month_window' => 6
      )
      expect(body).not_to have_key('isCerner')
    end

    it 'passes months query param through as month_count' do
      meta_twelve = summary_meta.merge(month_window: 12)
      allow(service).to receive(:summary).with(month_count: 12, status: nil).and_return(
        { entries: [], meta: meta_twelve }
      )

      get '/v1/medical_copays/summary', params: { months: 12 }

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body['meta']['month_window']).to eq(12)
    end

    context 'when summary raises ServiceError' do
      before do
        allow(service).to receive(:summary)
          .and_raise(MedicalCopays::LighthouseIntegration::Exceptions::ServiceError.new('External service error'))
      end

      it 'returns 502 with error payload' do
        get '/v1/medical_copays/summary'

        expect(response).to have_http_status(:bad_gateway)
        expect(JSON.parse(response.body)).to eq('error' => 'External service error')
      end
    end

    context 'when user has no ICN' do
      before do
        allow_any_instance_of(User).to receive(:icn).and_return(nil)
      end

      it 'returns forbidden' do
        get '/v1/medical_copays/summary'

        expect(response).to have_http_status(:forbidden)
      end
    end
  end
end
