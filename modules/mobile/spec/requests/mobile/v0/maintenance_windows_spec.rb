# frozen_string_literal: true

require_relative '../../../support/helpers/rails_helper'
require_relative '../../../support/helpers/committee_helper'

RSpec.describe 'Mobile::V0::MaintenanceWindows', type: :request do
  include CommitteeHelper

  def mw_uuid(service_name)
    Digest::UUID.uuid_v5(Mobile::V0::ServiceGraph::MAINTENANCE_WINDOW_NAMESPACE, service_name)
  end

  def affected_service_names
    get '/mobile/v0/maintenance_windows', headers: { 'X-Key-Inflection' => 'camel' }
    response.parsed_body['data'].pluck('attributes').pluck('service')
  end

  describe 'GET /v0/maintenance_windows' do
    context 'when no maintenance windows are active' do
      before { get '/mobile/v0/maintenance_windows', headers: { 'X-Key-Inflection' => 'camel' } }

      it 'matches the expected schema' do
        assert_schema_conform(200)
      end

      it 'returns an empty array of affected services' do
        expect(response.parsed_body['data']).to eq([])
      end
    end

    context 'when no maintenance windows that have not already ended are active' do
      before do
        Timecop.freeze('2021-05-26 22:33:39')

        create(:mobile_maintenance_lighthouse_first)
        get '/mobile/v0/maintenance_windows', headers: { 'X-Key-Inflection' => 'camel' }
      end

      after { Timecop.return }

      it 'matches the expected schema' do
        assert_schema_conform(200)
      end

      it 'returns an empty array of affected services' do
        expect(response.parsed_body['data']).to eq([])
      end
    end

    context 'when upstream maintenance windows affect multiple downstream services' do
      before do
        Timecop.freeze('2021-05-25T03:33:39Z')
        create(:mobile_maintenance_lighthouse_first)
        create(:mobile_maintenance_mpi)
        create(:mobile_maintenance_vbms)
        get '/mobile/v0/maintenance_windows', headers: { 'X-Key-Inflection' => 'camel' }
      end

      after { Timecop.return }

      it 'matches the expected schema' do
        assert_schema_conform(200)
      end

      it 'returns an array of the affected services' do
        expect(response.parsed_body['data']).to contain_exactly(
          {
            'id' => mw_uuid('claims'),
            'type' => 'maintenance_window',
            'attributes' => {
              'service' => 'claims',
              'startTime' => '2021-05-25T21:33:39.000Z',
              'endTime' => '2021-05-25T22:33:39.000Z'
            }
          }, {
            'id' => mw_uuid('direct_deposit_benefits'),
            'type' => 'maintenance_window',
            'attributes' => {
              'service' => 'direct_deposit_benefits',
              'startTime' => '2021-05-25T23:33:39.000Z',
              'endTime' => '2021-05-26T01:45:00.000Z'
            }
          }, {
            'id' => mw_uuid('immunizations'),
            'type' => 'maintenance_window',
            'attributes' => {
              'service' => 'immunizations',
              'startTime' => '2021-05-25T23:33:39.000Z',
              'endTime' => '2021-05-26T01:45:00.000Z'
            }
          }, {
            'id' => mw_uuid('allergies'),
            'type' => 'maintenance_window',
            'attributes' => {
              'service' => 'allergies',
              'startTime' => '2021-05-25T23:33:39.000Z',
              'endTime' => '2021-05-26T01:45:00.000Z'
            }
          }, {
            'id' => mw_uuid('labs_and_tests'),
            'type' => 'maintenance_window',
            'attributes' => {
              'service' => 'labs_and_tests',
              'startTime' => '2021-05-25T23:33:39.000Z',
              'endTime' => '2021-05-26T01:45:00.000Z'
            }
          }, {
            'id' => mw_uuid('letters_and_documents'),
            'type' => 'maintenance_window',
            'attributes' => {
              'service' => 'letters_and_documents',
              'startTime' => '2021-05-25T23:33:39.000Z',
              'endTime' => '2021-05-26T01:45:00.000Z'
            }
          }, {
            'id' => mw_uuid('disability_rating'),
            'type' => 'maintenance_window',
            'attributes' => {
              'service' => 'disability_rating',
              'startTime' => '2021-05-25T23:33:39.000Z',
              'endTime' => '2021-05-26T01:45:00.000Z'
            }
          }, {
            'id' => mw_uuid('efolder'),
            'type' => 'maintenance_window',
            'attributes' => {
              'service' => 'efolder',
              'startTime' => '2021-05-25T23:33:39.000Z',
              'endTime' => '2021-05-27T01:45:00.000Z'
            }
          }, {
            'id' => mw_uuid('power_of_attorney'),
            'type' => 'maintenance_window',
            'attributes' => {
              'service' => 'power_of_attorney',
              'startTime' => '2021-05-25T21:33:39.000Z',
              'endTime' => '2021-05-25T22:33:39.000Z'
            }
          }, {
            'id' => mw_uuid('decision_letters'),
            'type' => 'maintenance_window',
            'attributes' => {
              'service' => 'decision_letters',
              'startTime' => '2021-05-25T23:33:39.000Z',
              'endTime' => '2021-05-27T01:45:00.000Z'
            }
          }, {
            'id' => mw_uuid('veteran_status'),
            'type' => 'maintenance_window',
            'attributes' => {
              'service' => 'veteran_status',
              'startTime' => '2021-05-25T23:33:39.000Z',
              'endTime' => '2021-05-26T01:45:00.000Z'
            }
          }
        )
      end
    end

    context 'when efolder_use_lighthouse_benefits_documents_service is enabled and BGS is down' do
      before do
        allow(Flipper).to receive(:enabled?).with(:efolder_use_lighthouse_benefits_documents_service)
                                            .and_return(true)
        Timecop.freeze('2021-05-25T03:33:39Z')
        create(:mobile_maintenance_bgs_first)
        get '/mobile/v0/maintenance_windows', headers: { 'X-Key-Inflection' => 'camel' }
      end

      after { Timecop.return }

      it 'cascades the BGS outage to efolder via lighthouse_benefits_documents' do
        services = response.parsed_body['data'].pluck('attributes').pluck('service')
        expect(services).to include('efolder')
      end
    end

    context 'when efolder_use_lighthouse_benefits_documents_service is disabled and BGS is down' do
      before do
        allow(Flipper).to receive(:enabled?).with(:efolder_use_lighthouse_benefits_documents_service)
                                            .and_return(false)
        Timecop.freeze('2021-05-25T03:33:39Z')
        create(:mobile_maintenance_bgs_first)
        get '/mobile/v0/maintenance_windows', headers: { 'X-Key-Inflection' => 'camel' }
      end

      after { Timecop.return }

      it 'does not cascade the BGS outage to efolder' do
        services = response.parsed_body['data'].pluck('attributes').pluck('service')
        expect(services).not_to include('efolder')
      end
    end

    context 'when BGS is down' do
      before do
        Timecop.freeze('2021-05-25T03:33:39Z')
        create(:mobile_maintenance_bgs_first)
        get '/mobile/v0/maintenance_windows', headers: { 'X-Key-Inflection' => 'camel' }
      end

      after { Timecop.return }

      it 'matches the expected schema' do
        assert_schema_conform(200)
      end

      it 'includes payment history as an affected service' do
        expect(response.parsed_body['data']).to include(
          {
            'id' => mw_uuid('payment_history'),
            'type' => 'maintenance_window',
            'attributes' => {
              'service' => 'payment_history',
              'startTime' => '2021-05-25T23:33:39.000Z',
              'endTime' => '2021-05-26T01:45:00.000Z'
            }
          }
        )
      end
    end

    context 'when there are multiple windows for same service with different time spans' do
      let!(:earliest_lighthouse_starting) { create(:mobile_maintenance_lighthouse_first) }
      let!(:middle_lighthouse_starting) { create(:mobile_maintenance_lighthouse_second) }
      let!(:latest_lighthouse_starting) { create(:mobile_maintenance_lighthouse_third) }

      before { Timecop.freeze('2021-05-25T03:33:39Z') }
      after { Timecop.return }

      it 'shows closest window to now in the future' do
        get '/mobile/v0/maintenance_windows', headers: { 'X-Key-Inflection' => 'camel' }

        attributes = response.parsed_body['data'].pluck('attributes')
        lighthouse_earliest_start_time = earliest_lighthouse_starting.start_time.iso8601
        lighthouse_earliest_end_time = earliest_lighthouse_starting.end_time.iso8601
        lighthouse_middle_start_time = middle_lighthouse_starting.start_time.iso8601
        lighthouse_middle_end_time = middle_lighthouse_starting.end_time.iso8601
        lighthouse_latest_start_time = latest_lighthouse_starting.start_time.iso8601
        lighthouse_latest_end_time = latest_lighthouse_starting.end_time.iso8601

        assert_schema_conform(200)
        expect(attributes.pluck('service').uniq).to match_array(%w[claims power_of_attorney])
        expect(attributes.map { |w| Time.parse(w['startTime']).iso8601 }.uniq).to eq([lighthouse_earliest_start_time])
        expect(attributes.map { |w| Time.parse(w['endTime']).iso8601 }.uniq).to eq([lighthouse_earliest_end_time])

        Timecop.freeze('2021-05-26T03:33:39Z')
        get '/mobile/v0/maintenance_windows', headers: { 'X-Key-Inflection' => 'camel' }

        assert_schema_conform(200)
        attributes = response.parsed_body['data'].pluck('attributes')
        expect(attributes.pluck('service').uniq).to match_array(%w[claims power_of_attorney])
        expect(attributes.map { |w| Time.parse(w['startTime']).iso8601 }.uniq).to eq([lighthouse_middle_start_time])
        expect(attributes.map { |w| Time.parse(w['endTime']).iso8601 }.uniq).to eq([lighthouse_middle_end_time])

        Timecop.freeze('2021-05-27T03:33:39Z')
        get '/mobile/v0/maintenance_windows', headers: { 'X-Key-Inflection' => 'camel' }

        assert_schema_conform(200)
        attributes = response.parsed_body['data'].pluck('attributes')
        expect(attributes.pluck('service').uniq).to match_array(%w[claims power_of_attorney])

        expect(attributes.map { |w| Time.parse(w['startTime']).iso8601 }.uniq).to eq([lighthouse_latest_start_time])
        expect(attributes.map { |w| Time.parse(w['endTime']).iso8601 }.uniq).to eq([lighthouse_latest_end_time])
      end
    end

    context 'when there are multiple windows for various services with different time spans' do
      let!(:earliest_lighthouse_starting) { create(:mobile_maintenance_lighthouse_first) }
      let!(:latest_lighthouse_starting) { create(:mobile_maintenance_lighthouse_second) }
      let!(:earliest_bgs_starting) { create(:mobile_maintenance_bgs_first) }
      let!(:latest_bgs_starting) { create(:mobile_maintenance_bgs_second) }
      let(:lighthouse_services) { %w[claims].freeze }
      let(:bgs_services) { %w[payment_history appeals].freeze }

      before { Timecop.freeze('2021-05-25T03:33:39Z') }
      after { Timecop.return }

      it 'shows closest window to now in the future' do
        get '/mobile/v0/maintenance_windows', headers: { 'X-Key-Inflection' => 'camel' }

        attributes = response.parsed_body['data'].pluck('attributes')
        lighthouse_windows = attributes.select { |window| lighthouse_services.include?(window['service']) }
        bgs_windows = attributes.select { |window| bgs_services.include?(window['service']) }
        lighthouse_earliest_start_time = earliest_lighthouse_starting.start_time.iso8601
        lighthouse_earliest_end_time = earliest_lighthouse_starting.end_time.iso8601
        bgs_earliest_start_time = earliest_bgs_starting.start_time.iso8601
        bgs_earliest_end_time = earliest_bgs_starting.end_time.iso8601

        assert_schema_conform(200)
        expect(lighthouse_windows.pluck('service')).to eq(lighthouse_services)
        expect(lighthouse_windows.map do |w|
          Time.parse(w['startTime']).iso8601
        end.uniq).to eq([lighthouse_earliest_start_time])
        expect(lighthouse_windows.map do |w|
          Time.parse(w['endTime']).iso8601
        end.uniq).to eq([lighthouse_earliest_end_time])
        expect(bgs_windows.pluck('service')).to eq(bgs_services)
        expect(bgs_windows.map { |w| Time.parse(w['startTime']).iso8601 }.uniq).to eq([bgs_earliest_start_time])
        expect(bgs_windows.map { |w| Time.parse(w['endTime']).iso8601 }.uniq).to eq([bgs_earliest_end_time])

        Timecop.freeze('2021-05-26 03:45:00')
        get '/mobile/v0/maintenance_windows', headers: { 'X-Key-Inflection' => 'camel' }

        attributes = response.parsed_body['data'].pluck('attributes')
        lighthouse_windows = attributes.select { |window| lighthouse_services.include?(window['service']) }
        bgs_windows = attributes.select { |window| bgs_services.include?(window['service']) }
        lighthouse_latest_start_time = latest_lighthouse_starting.start_time.iso8601
        lighthouse_latest_end_time = latest_lighthouse_starting.end_time.iso8601
        bgs_latest_start_time = latest_bgs_starting.start_time.iso8601
        bgs_latest_end_time = latest_bgs_starting.end_time.iso8601

        assert_schema_conform(200)
        expect(lighthouse_windows.pluck('service')).to eq(lighthouse_services)
        expect(lighthouse_windows.map do |w|
          Time.parse(w['startTime']).iso8601
        end.uniq).to eq([lighthouse_latest_start_time])
        expect(lighthouse_windows.map { |w| Time.parse(w['endTime']).iso8601 }.uniq).to eq([lighthouse_latest_end_time])
        expect(bgs_windows.pluck('service')).to eq(bgs_services)
        expect(bgs_windows.map { |w| Time.parse(w['startTime']).iso8601 }.uniq).to eq([bgs_latest_start_time])
        expect(bgs_windows.map { |w| Time.parse(w['endTime']).iso8601 }.uniq).to eq([bgs_latest_end_time])
      end
    end

    context 'when a newly mapped upstream service is down' do
      before { Timecop.freeze('2021-05-25T03:33:39Z') }
      after { Timecop.return }

      it 'cascades a VAOS outage to appointments, facilities_info, and referrals (via ccra)' do
        create(:mobile_maintenance_vaos)
        expect(affected_service_names).to include('appointments', 'facilities_info', 'referrals')
      end

      it 'cascades a CCRA outage to referrals' do
        create(:mobile_maintenance_ccra)
        expect(affected_service_names).to include('referrals')
      end

      {
        mobile_maintenance_dmc: 'debts',
        mobile_maintenance_vbs: 'medical_copays',
        mobile_maintenance_vetext: 'push_prefs'
      }.each do |factory, service|
        it "surfaces #{service} when its upstream is down" do
          create(factory)
          expect(affected_service_names).to include(service)
        end
      end
    end
  end
end
