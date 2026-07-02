# frozen_string_literal: true

require 'rails_helper'

RSpec.describe VAOS::V2::ReferralsController, type: :request do
  let(:memory_store) { ActiveSupport::Cache.lookup_store(:memory_store) }
  let(:referral_number) { '5682' }
  let(:referral_consult_id) { '984_646372' }
  let(:encrypted_referral_consult_id) { 'encrypted-984_646372' }
  let(:inflection_header) { { 'X-Key-Inflection' => 'camel' } }
  let(:referral_statuses) { "'AP', 'C'" }
  let(:icn) { '1012845331V153043' }

  before do
    allow(Rails).to receive(:cache).and_return(memory_store)
    Rails.cache.clear
    allow(VAOS::ReferralEncryptionService)
      .to receive(:encrypt)
      .with(referral_consult_id)
      .and_return(encrypted_referral_consult_id)
    allow(VAOS::ReferralEncryptionService)
      .to receive(:decrypt)
      .with(encrypted_referral_consult_id)
      .and_return(referral_consult_id)
  end

  describe 'GET index' do
    context 'when called without authorization' do
      let(:resp) do
        {
          'errors' => [
            {
              'title' => 'Not authorized',
              'detail' => 'Not authorized',
              'code' => '401',
              'status' => '401'
            }
          ]
        }
      end

      it 'throws unauthorized exception' do
        get '/vaos/v2/referrals'

        expect(response).to have_http_status(:unauthorized)
        expect(JSON.parse(response.body)).to eq(resp)
      end
    end

    context 'when called with authorization' do
      let(:user) { build(:user, :vaos, :loa3, icn:) }
      let(:referral_list_entries) { build_list(:ccra_referral_list_entry, 3) }
      let(:empty_appointments_response) { { EPS: { data: [] }, VAOS: { data: [] } } }

      before do
        sign_in_as(user)
        allow_any_instance_of(Ccra::ReferralService).to receive(:get_vaos_referral_list)
          .with(icn, referral_statuses)
          .and_return(referral_list_entries)
        allow_any_instance_of(VAOS::V2::AppointmentsService).to receive(:get_active_appointments_for_referral)
          .and_return(empty_appointments_response)
        allow_any_instance_of(VAOS::V2::AppointmentsService).to receive(:active_appointment_for_referral?)
          .and_return(false)
        allow(Flipper).to receive(:enabled?).and_call_original
        allow(Flipper).to receive(:enabled?)
          .with(:va_online_scheduling_referral_list_has_appointments, anything)
          .and_return(true)
      end

      it 'returns a list of referrals in JSON:API format' do
        get '/vaos/v2/referrals'

        expect(response).to have_http_status(:ok)

        response_data = JSON.parse(response.body)
        expect(response_data).to have_key('data')
        expect(response_data['data']).to be_an(Array)
        expect(response_data['data'].size).to eq(3)

        # Verify first referral entry structure
        first_referral = response_data['data'].first
        expect(first_referral['id']).to eq(encrypted_referral_consult_id)
        expect(first_referral['type']).to eq('referrals')
        expect(first_referral['attributes']['categoryOfCare']).to eq('CARDIOLOGY')
        expect(first_referral['attributes']['referralNumber']).to eq('5682')
        expect(first_referral['attributes']['referralConsultId']).to eq(referral_consult_id)
        expect(first_referral['attributes']['expirationDate']).to eq((Date.current + 60.days).strftime('%Y-%m-%d'))
        expect(first_referral['attributes']['hasAppointments']).to be(false)
        expect(first_referral['attributes']['onlineSchedule']).to be(false)
      end

      it 'logs multiple referrals count with JSON structured format and records StatsD gauge' do
        expected_count = 3
        expected_log_message = "CCRA referrals retrieved: #{expected_count}"
        expected_json_data = { referral_count: expected_count }.to_json

        expect(Rails.logger).to receive(:info).with(expected_log_message, expected_json_data)
        expect(StatsD).to receive(:gauge).with(
          'api.vaos.referrals.retrieved',
          expected_count,
          tags: ['has_referrals:true']
        )

        get '/vaos/v2/referrals'

        expect(response).to have_http_status(:ok)
      end

      context 'when testing referral count logging and StatsD metrics' do
        context 'with zero referrals' do
          let(:empty_referral_list) { [] }

          before do
            allow_any_instance_of(Ccra::ReferralService).to receive(:get_vaos_referral_list)
              .with(icn, referral_statuses)
              .and_return(empty_referral_list)
          end

          it 'logs zero count with JSON structured format and records StatsD gauge with has_referrals:false' do
            expected_count = 0
            expected_log_message = "CCRA referrals retrieved: #{expected_count}"
            expected_json_data = { referral_count: expected_count }.to_json

            expect(Rails.logger).to receive(:info).with(expected_log_message, expected_json_data)
            expect(StatsD).to receive(:gauge).with(
              'api.vaos.referrals.retrieved',
              expected_count,
              tags: ['has_referrals:false']
            )

            get '/vaos/v2/referrals'

            expect(response).to have_http_status(:ok)
            response_data = JSON.parse(response.body)
            expect(response_data['data']).to be_empty
          end
        end

        context 'with one referral' do
          let(:single_referral_list) { build_list(:ccra_referral_list_entry, 1) }

          before do
            allow_any_instance_of(Ccra::ReferralService).to receive(:get_vaos_referral_list)
              .with(icn, referral_statuses)
              .and_return(single_referral_list)
          end

          it 'logs single count with JSON structured format and records StatsD gauge with has_referrals:true' do
            expected_count = 1
            expected_log_message = "CCRA referrals retrieved: #{expected_count}"
            expected_json_data = { referral_count: expected_count }.to_json

            expect(Rails.logger).to receive(:info).with(expected_log_message, expected_json_data)
            expect(StatsD).to receive(:gauge).with(
              'api.vaos.referrals.retrieved',
              expected_count,
              tags: ['has_referrals:true']
            )

            get '/vaos/v2/referrals'

            expect(response).to have_http_status(:ok)
            response_data = JSON.parse(response.body)
            expect(response_data['data'].size).to eq(1)
          end
        end

        context 'with multiple referrals' do
          let(:multiple_referrals_list) { build_list(:ccra_referral_list_entry, 5) }

          before do
            allow_any_instance_of(Ccra::ReferralService).to receive(:get_vaos_referral_list)
              .with(icn, referral_statuses)
              .and_return(multiple_referrals_list)
          end

          it 'logs multiple count with JSON structured format and records StatsD gauge with has_referrals:true' do
            expected_count = 5
            expected_log_message = "CCRA referrals retrieved: #{expected_count}"
            expected_json_data = { referral_count: expected_count }.to_json

            expect(Rails.logger).to receive(:info).with(expected_log_message, expected_json_data)
            expect(StatsD).to receive(:gauge).with(
              'api.vaos.referrals.retrieved',
              expected_count,
              tags: ['has_referrals:true']
            )

            get '/vaos/v2/referrals'

            expect(response).to have_http_status(:ok)
            response_data = JSON.parse(response.body)
            expect(response_data['data'].size).to eq(5)
          end
        end

        context 'when service returns nil' do
          before do
            allow_any_instance_of(Ccra::ReferralService).to receive(:get_vaos_referral_list)
              .with(icn, referral_statuses)
              .and_return(nil)
          end

          it 'logs zero count when service returns nil' do
            expected_count = 0
            expected_log_message = "CCRA referrals retrieved: #{expected_count}"
            expected_json_data = { referral_count: expected_count }.to_json

            expect(Rails.logger).to receive(:info).with(expected_log_message, expected_json_data)
            expect(StatsD).to receive(:gauge).with(
              'api.vaos.referrals.retrieved',
              expected_count,
              tags: ['has_referrals:false']
            )

            get '/vaos/v2/referrals'

            expect(response).to have_http_status(:ok)
          end
        end
      end

      context 'with a custom status parameter' do
        let(:custom_statuses) { "'A','I'" }

        before do
          allow_any_instance_of(Ccra::ReferralService).to receive(:get_vaos_referral_list)
            .with(icn, custom_statuses)
            .and_return(referral_list_entries)
        end

        it 'passes the correct status to the service' do
          get '/vaos/v2/referrals', params: { status: custom_statuses }

          expect(response).to have_http_status(:ok)
        end
      end

      context 'when filtering expired referrals' do
        let(:today) { Time.zone.today }
        let(:expired_referral) do
          # Create a referral that expired yesterday
          build(:ccra_referral_list_entry,
                referral_expiration_date: (today - 1.day).to_s)
        end
        let(:active_referral) do
          # Create a referral that expires 30 days from now
          build(:ccra_referral_list_entry,
                referral_expiration_date: (today + 30.days).to_s)
        end
        let(:mixed_referrals) { [expired_referral, active_referral] }

        before do
          allow_any_instance_of(Ccra::ReferralService).to receive(:get_vaos_referral_list)
            .with(icn, referral_statuses)
            .and_return(mixed_referrals)
        end

        it 'filters out expired referrals automatically' do
          get '/vaos/v2/referrals'

          expect(response).to have_http_status(:ok)

          response_data = JSON.parse(response.body)
          expect(response_data['data'].size).to eq(1)
          # The active referral should have an expiration date 30 days from today
          expect(Date.parse(response_data['data'].first['attributes']['expirationDate'])).to eq(today + 30.days)
        end
      end

      context 'when all referrals are expired' do
        let(:today) { Time.zone.today }
        let(:all_expired_referrals) do
          [
            # Expired 1 day ago
            build(:ccra_referral_list_entry,
                  referral_expiration_date: (today - 1.day).to_s),
            # Expired 5 days ago
            build(:ccra_referral_list_entry,
                  referral_expiration_date: (today - 5.days).to_s)
          ]
        end

        before do
          allow_any_instance_of(Ccra::ReferralService).to receive(:get_vaos_referral_list)
            .with(icn, referral_statuses)
            .and_return(all_expired_referrals)
        end

        it 'returns an empty data array' do
          get '/vaos/v2/referrals'

          expect(response).to have_http_status(:ok)

          response_data = JSON.parse(response.body)
          expect(response_data['data']).to be_an(Array)
          expect(response_data['data']).to be_empty
        end
      end

      context 'when annotating has_appointments per referral' do
        let(:referral_a) do
          build(:ccra_referral_list_entry, referral_number: 'REF-A', referral_consult_id: 'consult-a')
        end
        let(:referral_b) do
          build(:ccra_referral_list_entry, referral_number: 'REF-B', referral_consult_id: 'consult-b')
        end
        let(:mixed_referrals) { [referral_a, referral_b] }

        before do
          allow(VAOS::ReferralEncryptionService).to receive(:encrypt).with('consult-a').and_return('encrypted-a')
          allow(VAOS::ReferralEncryptionService).to receive(:encrypt).with('consult-b').and_return('encrypted-b')
          allow_any_instance_of(Ccra::ReferralService).to receive(:get_vaos_referral_list)
            .with(icn, referral_statuses)
            .and_return(mixed_referrals)
        end

        context 'when a referral has an active appointment' do
          before do
            allow_any_instance_of(VAOS::V2::AppointmentsService).to receive(:active_appointment_for_referral?)
              .with('REF-A')
              .and_return(true)
            allow_any_instance_of(VAOS::V2::AppointmentsService).to receive(:active_appointment_for_referral?)
              .with('REF-B')
              .and_return(false)
          end

          it 'sets hasAppointments to true only for that referral' do
            get '/vaos/v2/referrals'

            expect(response).to have_http_status(:ok)
            data = JSON.parse(response.body)['data']
            attrs_a = data.find { |d| d['attributes']['referralNumber'] == 'REF-A' }['attributes']
            attrs_b = data.find { |d| d['attributes']['referralNumber'] == 'REF-B' }['attributes']
            expect(attrs_a['hasAppointments']).to be(true)
            expect(attrs_b['hasAppointments']).to be(false)
          end
        end

        context 'when a referral has only cancelled appointments' do
          before do
            allow_any_instance_of(VAOS::V2::AppointmentsService).to receive(:active_appointment_for_referral?)
              .and_return(false)
          end

          it 'sets hasAppointments to false' do
            get '/vaos/v2/referrals'

            expect(response).to have_http_status(:ok)
            data = JSON.parse(response.body)['data']
            expect(data.map { |d| d['attributes']['hasAppointments'] }).to all(be(false))
          end
        end

        context 'when the appointments service raises for one referral' do
          let(:failure_metric) { 'api.vaos.referral_list.has_appointments_lookup.failure' }

          before do
            allow_any_instance_of(VAOS::V2::AppointmentsService).to receive(:active_appointment_for_referral?)
              .with('REF-A')
              .and_raise(Common::Exceptions::BackendServiceException.new('VAOS_502', { source: 'EPS' }))
            allow_any_instance_of(VAOS::V2::AppointmentsService).to receive(:active_appointment_for_referral?)
              .with('REF-B')
              .and_return(true)
          end

          it 'returns 200 with all referrals, leaves the failing one as nil, and logs a PII-safe warning' do
            allow(StatsD).to receive(:increment)
            allow(StatsD).to receive(:gauge)
            expect(Rails.logger).to receive(:warn) do |message, payload|
              expect(message).to eq(
                'Community Care Appointments: Failed to fetch appointments for referral list entry'
              )
              expect(payload.keys).to contain_exactly(:error_class, :station_id, :user_uuid)
              expect(payload[:error_class]).to eq('Common::Exceptions::BackendServiceException')
              expect(payload[:user_uuid]).to eq(user.uuid)
              expect(payload).not_to have_key(:referral_number)
              expect(payload).not_to have_key(:referral_consult_id)
              expect(payload).not_to have_key(:uuid)
            end
            expect(StatsD).to receive(:increment).with(failure_metric)

            get '/vaos/v2/referrals'

            expect(response).to have_http_status(:ok)
            data = JSON.parse(response.body)['data']
            expect(data.size).to eq(2)
            attrs_a = data.find { |d| d['attributes']['referralNumber'] == 'REF-A' }['attributes']
            attrs_b = data.find { |d| d['attributes']['referralNumber'] == 'REF-B' }['attributes']
            expect(attrs_a['hasAppointments']).to be_nil
            expect(attrs_b['hasAppointments']).to be(true)
          end
        end
      end

      context 'when a referral is missing scheduling-critical data' do
        let(:incomplete_referral) do
          build(:ccra_referral_list_entry,
                category_of_care: nil,
                referral_expiration_date: nil,
                station_id: '528A6')
        end
        let(:referral_list_entries) { [incomplete_referral] }

        before do
          allow_any_instance_of(Ccra::ReferralService).to receive(:get_vaos_referral_list)
            .with(icn, referral_statuses)
            .and_return(referral_list_entries)
        end

        it 'logs missing referral data and increments the missing_data metric' do
          expect(Rails.logger).to receive(:error).with(
            VAOS::V2::ReferralMissingDataMonitor::LIST_LOG_MESSAGE,
            {
              missing_data: %w[category_of_care expiration_date],
              station_id: '528A6',
              user_uuid: user.uuid
            }
          )
          expect(StatsD).to receive(:increment).with(
            VAOS::V2::ReferralMissingDataMonitor::LIST_METRIC,
            tags: [
              'service:community_care_appointments',
              'station_id:528A6'
            ]
          )
          allow(StatsD).to receive(:increment)

          get '/vaos/v2/referrals'

          expect(response).to have_http_status(:ok)
        end
      end

      context 'when va_online_scheduling_referral_list_has_appointments is disabled' do
        before do
          allow(Flipper).to receive(:enabled?).and_call_original
          allow(Flipper).to receive(:enabled?)
            .with(:va_online_scheduling_referral_list_has_appointments, anything)
            .and_return(false)
        end

        it 'skips the appointments lookup and leaves hasAppointments as nil' do
          expect_any_instance_of(VAOS::V2::AppointmentsService)
            .not_to receive(:active_appointment_for_referral?)

          get '/vaos/v2/referrals'

          expect(response).to have_http_status(:ok)
          data = JSON.parse(response.body)['data']
          expect(data).not_to be_empty
          expect(data.map { |d| d['attributes']['hasAppointments'] }).to all(be_nil)
        end
      end
    end
  end

  describe 'GET show' do
    context 'when called without authorization' do
      let(:resp) do
        {
          'errors' => [
            {
              'title' => 'Not authorized',
              'detail' => 'Not authorized',
              'code' => '401',
              'status' => '401'
            }
          ]
        }
      end

      it 'throws unauthorized exception' do
        get "/vaos/v2/referrals/#{encrypted_referral_consult_id}"

        expect(response).to have_http_status(:unauthorized)
        expect(JSON.parse(response.body)).to eq(resp)
      end
    end

    context 'when called with authorization' do
      let(:user) { build(:user, :vaos, :loa3, icn:) }
      let(:referral_detail) { build(:ccra_referral_detail, referral_consult_id:, referral_number:) }

      before do
        sign_in_as(user)
        allow_any_instance_of(Ccra::ReferralService).to receive(:get_referral)
          .with(referral_consult_id, icn)
          .and_return(referral_detail)
        allow_any_instance_of(VAOS::V2::AppointmentsService).to receive(:get_active_appointments_for_referral)
          .with(referral_number)
          .and_return({ EPS: { data: [] }, VAOS: { data: [] } })
      end

      it 'returns a referral detail in JSON:API format' do
        get "/vaos/v2/referrals/#{encrypted_referral_consult_id}"

        expect(response).to have_http_status(:ok)

        response_data = JSON.parse(response.body)
        expect(response_data).to have_key('data')
        expect(response_data['data']['id']).to eq(encrypted_referral_consult_id)
        expect(response_data['data']['type']).to eq('referrals')
        expect(response_data['data']['attributes']['categoryOfCare']).to eq('CARDIOLOGY')
        expect(response_data['data']['attributes']['onlineSchedule']).to be(false)
        expect(response_data['data']['attributes']['provider']['name']).to eq('Dr. Smith')
        expect(response_data['data']['attributes']['referringFacility']['name']).to be_present
        expect(response_data['data']['attributes']['expirationDate']).to be_a(String)
        expect(response_data['data']['attributes']['referralNumber']).to eq(referral_number)
        expect(response_data['data']['attributes']['referralConsultId']).to eq(referral_consult_id)
        expect(response_data['data']['attributes']).to have_key('appointments')
        expect(response_data['data']['attributes']['appointments']).to eq({
                                                                            'EPS' => { 'data' => [] },
                                                                            'VAOS' => { 'data' => [] }
                                                                          })
      end

      context 'when EPS and VAOS have active appointments' do
        before do
          allow_any_instance_of(VAOS::V2::AppointmentsService).to receive(:get_active_appointments_for_referral)
            .with(referral_number)
            .and_return({
                          EPS: {
                            data: [
                              { id: 'eps-123', status: 'active', start: '2021-09-05T10:00:00Z' },
                              { id: 'eps-456', status: 'cancelled', start: '2021-09-06T10:00:00Z' }
                            ]
                          },
                          VAOS: {
                            data: [
                              { id: 'vaos-789', status: 'active', start: '2021-09-07T10:00:00Z' }
                            ]
                          }
                        })
        end

        it 'returns appointments from both sources' do
          get "/vaos/v2/referrals/#{encrypted_referral_consult_id}"

          expect(response).to have_http_status(:ok)
          response_data = JSON.parse(response.body)

          expect(response_data['data']['attributes']['appointments']).to eq({
                                                                              'EPS' => {
                                                                                'data' => [
                                                                                  {
                                                                                    'id' => 'eps-123',
                                                                                    'status' => 'active',
                                                                                    'start' => '2021-09-05T10:00:00Z'
                                                                                  },
                                                                                  {
                                                                                    'id' => 'eps-456',
                                                                                    'status' => 'cancelled',
                                                                                    'start' => '2021-09-06T10:00:00Z'
                                                                                  }
                                                                                ]
                                                                              },
                                                                              'VAOS' => {
                                                                                'data' => [
                                                                                  {
                                                                                    'id' => 'vaos-789',
                                                                                    'status' => 'active',
                                                                                    'start' => '2021-09-07T10:00:00Z'
                                                                                  }
                                                                                ]
                                                                              }
                                                                            })
        end
      end

      it 'sets the booking start time in the cache' do
        client = Ccra::RedisClient.new

        Timecop.freeze do
          expect_any_instance_of(Ccra::ReferralService).to receive(:get_referral) do |_service, id, user_icn|
            expect(id).to eq(referral_consult_id)
            expect(user_icn).to eq(icn)
            # Simulate the service saving the booking start time
            client.save_booking_start_time(
              referral_number:,
              booking_start_time: Time.current.to_f
            )
            referral_detail
          end

          expect do
            get "/vaos/v2/referrals/#{encrypted_referral_consult_id}"
          end.to change {
            client.fetch_booking_start_time(referral_number:)
          }.from(nil).to(Time.current.to_f)
        end
      end

      it 'increments the referral detail page access metric' do
        expect(StatsD).to receive(:increment)
          .with(
            described_class::REFERRAL_DETAIL_VIEW_METRIC,
            tags: [
              'service:community_care_appointments',
              'referring_facility_code:552',
              'station_id:528A6',
              'type_of_care:CARDIOLOGY'
            ]
          )

        expect(StatsD).to receive(:increment).with('api.rack.request', any_args)

        get "/vaos/v2/referrals/#{encrypted_referral_consult_id}"
      end

      context 'when testing structured logging for missing provider data' do
        let(:referral_detail_missing_data) do
          build(:ccra_referral_detail,
                referral_consult_id:,
                referral_number:).tap do |referral|
            # Override the referring facility code by setting it directly
            referral.instance_variable_set(:@referring_facility_code, nil)
            # Override the provider NPI by setting it directly
            referral.instance_variable_set(:@provider_npi, '')
          end
        end

        before do
          allow_any_instance_of(Ccra::ReferralService).to receive(:get_referral)
            .with(referral_consult_id, icn)
            .and_return(referral_detail_missing_data)
          allow_any_instance_of(VAOS::V2::AppointmentsService).to receive(:get_active_appointments_for_referral)
            .with(referral_number)
            .and_return({ EPS: { data: [] }, VAOS: { data: [] } })
        end

        it 'logs missing provider data with JSON structured format' do
          expected_error_message = VAOS::V2::ReferralMissingDataMonitor::DETAIL_LOG_MESSAGE
          expected_json_data = {
            missing_data: %w[referring_facility_code referral_provider_npi],
            station_id: '528A6',
            user_uuid: user.uuid
          }

          expect(Rails.logger).to receive(:error).with(expected_error_message, expected_json_data)
          expect(StatsD).to receive(:increment).with(
            VAOS::V2::ReferralMissingDataMonitor::DETAIL_METRIC,
            tags: [
              'service:community_care_appointments',
              'station_id:528A6'
            ]
          )
          expect(StatsD).to receive(:increment)
            .with(
              described_class::REFERRAL_DETAIL_VIEW_METRIC,
              tags: [
                'service:community_care_appointments',
                'referring_facility_code:no_value',
                'station_id:528A6',
                'type_of_care:CARDIOLOGY'
              ]
            )
          # Allow for middleware StatsD calls
          allow(StatsD).to receive(:increment).with('api.rack.request', any_args)

          get "/vaos/v2/referrals/#{encrypted_referral_consult_id}"

          expect(response).to have_http_status(:ok)
        end

        context 'when only referring facility code is missing' do
          let(:referral_detail_partial_missing) do
            build(:ccra_referral_detail,
                  referral_consult_id:,
                  referral_number:).tap do |referral|
              # Override the referring facility code by setting it directly
              referral.instance_variable_set(:@referring_facility_code, nil)
              # Keep the provider NPI as is from factory (should be '1234567890')
            end
          end

          before do
            allow_any_instance_of(Ccra::ReferralService).to receive(:get_referral)
              .with(referral_consult_id, icn)
              .and_return(referral_detail_partial_missing)
            allow_any_instance_of(VAOS::V2::AppointmentsService).to receive(:get_active_appointments_for_referral)
              .with(referral_number)
              .and_return({ EPS: { data: [] }, VAOS: { data: [] } })
          end

          it 'logs only the missing referring facility code in structured format' do
            expected_error_message = VAOS::V2::ReferralMissingDataMonitor::DETAIL_LOG_MESSAGE
            expected_json_data = {
              missing_data: ['referring_facility_code'],
              station_id: '528A6',
              user_uuid: user.uuid
            }

            expect(Rails.logger).to receive(:error).with(expected_error_message, expected_json_data)
            expect(StatsD).to receive(:increment).with(
              VAOS::V2::ReferralMissingDataMonitor::DETAIL_METRIC,
              tags: [
                'service:community_care_appointments',
                'station_id:528A6'
              ]
            )
            allow(StatsD).to receive(:increment)

            get "/vaos/v2/referrals/#{encrypted_referral_consult_id}"

            expect(response).to have_http_status(:ok)
          end
        end

        context 'when no provider data is missing' do
          before do
            # Override the mock to return the default referral detail (which has complete data)
            allow_any_instance_of(Ccra::ReferralService).to receive(:get_referral)
              .with(referral_consult_id, icn)
              .and_return(referral_detail)
            allow_any_instance_of(VAOS::V2::AppointmentsService).to receive(:get_active_appointments_for_referral)
              .with(referral_number)
              .and_return({ EPS: { data: [] }, VAOS: { data: [] } })
          end

          it 'does not log any missing referral data errors' do
            expect(Rails.logger).not_to receive(:error)
              .with(VAOS::V2::ReferralMissingDataMonitor::DETAIL_LOG_MESSAGE, anything)
            expect(StatsD).not_to receive(:increment)
              .with(VAOS::V2::ReferralMissingDataMonitor::DETAIL_METRIC, anything)

            get "/vaos/v2/referrals/#{encrypted_referral_consult_id}"

            expect(response).to have_http_status(:ok)
          end
        end
      end

      context 'when the appointments service raises a BackendServiceException' do
        before do
          allow_any_instance_of(VAOS::V2::AppointmentsService).to receive(:get_active_appointments_for_referral)
            .with(referral_number)
            .and_raise(Common::Exceptions::BackendServiceException.new('VAOS_502', { source: 'EPS' }))
        end

        it 'lets the exception bubble up instead of rescuing it' do
          get "/vaos/v2/referrals/#{encrypted_referral_consult_id}"

          expect(response).to have_http_status(:bad_gateway)
        end
      end
    end
  end
end
