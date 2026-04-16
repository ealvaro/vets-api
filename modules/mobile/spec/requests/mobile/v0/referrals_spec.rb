# frozen_string_literal: true

require_relative '../../../support/helpers/rails_helper'
require_relative '../../../support/helpers/committee_helper'

RSpec.describe 'Mobile::V0::Referrals', type: :request do
  include CommitteeHelper

  let!(:user) { sis_user }
  let(:referral_service_double) { instance_double(Ccra::ReferralService) }
  let(:appointments_service_double) { instance_double(VAOS::V2::AppointmentsService) }
  let(:empty_appointments) { { EPS: { data: [] }, VAOS: { data: [] } } }

  before do
    allow(Ccra::ReferralService).to receive(:new).and_return(referral_service_double)
    allow(VAOS::V2::AppointmentsService).to receive(:new).and_return(appointments_service_double)
  end

  describe 'GET /mobile/v0/referrals' do
    let(:referrals) { build_list(:ccra_referral_list_entry, 3, category_of_care: 'primary care', station_id: '984') }

    before do
      allow(referral_service_double).to receive(:get_vaos_referral_list).and_return(referrals)
      referrals.each do |referral|
        allow(VAOS::ReferralEncryptionService).to receive(:encrypt)
          .with(referral.referral_consult_id)
          .and_return("encrypted-#{referral.referral_consult_id}")
      end
    end

    context 'when the user is not authenticated' do
      it 'returns unauthorized' do
        get '/mobile/v0/referrals'
        assert_schema_conform(401)
      end
    end

    context 'when the user is authenticated' do
      it 'increments the total counter' do
        expect { get '/mobile/v0/referrals', headers: sis_headers }
          .to trigger_statsd_increment('mobile.referrals.index.total')
      end

      it 'records the referral count gauge' do
        expect { get '/mobile/v0/referrals', headers: sis_headers }
          .to trigger_statsd_gauge('mobile.referrals.index.count', value: 3)
      end

      it 'returns a list of referrals' do
        get '/mobile/v0/referrals', headers: sis_headers

        expect(response).to have_http_status(:ok)
        assert_schema_conform(200)

        json = response.parsed_body
        expect(json['data'].length).to eq(3)
        expect(json['data'].first['type']).to eq('referrals')
        expect(json['data'].first['attributes']).to have_key('categoryOfCare')
        expect(json['data'].first['attributes']).to have_key('referralNumber')
      end

      it 'adds encrypted uuids to each referral' do
        get '/mobile/v0/referrals', headers: sis_headers

        json = response.parsed_body
        json['data'].each do |referral|
          expect(referral['id']).to start_with('encrypted-')
        end
      end

      context 'when there are expired referrals' do
        let(:active_referral) do
          build(:ccra_referral_list_entry, category_of_care: 'primary care', station_id: '984',
                                           referral_expiration_date: (Date.current + 30.days).to_s)
        end
        let(:expired_referral) do
          build(:ccra_referral_list_entry, category_of_care: 'primary care', station_id: '984',
                                           referral_expiration_date: (Date.current - 1.day).to_s)
        end

        before do
          allow(referral_service_double).to receive(:get_vaos_referral_list).and_return([active_referral,
                                                                                         expired_referral])
          allow(VAOS::ReferralEncryptionService).to receive(:encrypt).and_return('encrypted-id')
        end

        it 'filters out expired referrals' do
          get '/mobile/v0/referrals', headers: sis_headers

          json = response.parsed_body
          expect(json['data'].length).to eq(1)
        end
      end

      context 'when there are referrals with unsupported categories of care' do
        let(:supported_referral) do
          build(:ccra_referral_list_entry, category_of_care: 'primary care', station_id: '984')
        end
        let(:unsupported_referral) do
          build(:ccra_referral_list_entry, category_of_care: 'cardiology', station_id: '984')
        end

        before do
          allow(referral_service_double).to receive(:get_vaos_referral_list)
            .and_return([supported_referral, unsupported_referral])
          allow(VAOS::ReferralEncryptionService).to receive(:encrypt).and_return('encrypted-id')
        end

        it 'only returns referrals with supported categories of care' do
          get '/mobile/v0/referrals', headers: sis_headers

          json = response.parsed_body
          expect(json['data'].length).to eq(1)
        end
      end

      context 'when there are referrals with unsupported station IDs' do
        let(:supported_referral) do
          build(:ccra_referral_list_entry, category_of_care: 'primary care', station_id: '984')
        end
        let(:unsupported_referral) do
          build(:ccra_referral_list_entry, category_of_care: 'primary care', station_id: '999')
        end

        before do
          allow(referral_service_double).to receive(:get_vaos_referral_list)
            .and_return([supported_referral, unsupported_referral])
          allow(VAOS::ReferralEncryptionService).to receive(:encrypt).and_return('encrypted-id')
        end

        it 'only returns referrals with supported station IDs' do
          get '/mobile/v0/referrals', headers: sis_headers

          json = response.parsed_body
          expect(json['data'].length).to eq(1)
        end
      end

      context 'when there are no referrals' do
        before do
          allow(referral_service_double).to receive(:get_vaos_referral_list).and_return([])
        end

        it 'returns an empty list' do
          get '/mobile/v0/referrals', headers: sis_headers

          expect(response).to have_http_status(:ok)
          assert_schema_conform(200)

          json = response.parsed_body
          expect(json['data']).to eq([])
        end
      end

      context 'when the service raises an error' do
        before do
          allow(referral_service_double).to receive(:get_vaos_referral_list).and_raise(StandardError, 'service error')
        end

        it 'increments the failure counter' do
          expect { get '/mobile/v0/referrals', headers: sis_headers }
            .to trigger_statsd_increment('mobile.referrals.index.failure')
        end
      end
    end
  end

  describe 'GET /mobile/v0/referrals/:id' do
    let(:encrypted_id) { 'encrypted-984_646372' }
    let(:decrypted_id) { '984_646372' }
    let(:referral) { build(:ccra_referral_detail) }

    before do
      allow(VAOS::ReferralEncryptionService).to receive(:decrypt).with(encrypted_id).and_return(decrypted_id)
      allow(referral_service_double).to receive(:get_referral).with(decrypted_id, user.icn).and_return(referral)
      allow(appointments_service_double).to receive(:get_active_appointments_for_referral)
        .and_return(empty_appointments)
    end

    context 'when the user is not authenticated' do
      it 'returns unauthorized' do
        get "/mobile/v0/referrals/#{encrypted_id}"
        assert_schema_conform(401)
      end
    end

    context 'when the user is authenticated' do
      it 'increments the total counter' do
        expect { get "/mobile/v0/referrals/#{encrypted_id}", headers: sis_headers }
          .to trigger_statsd_increment('mobile.referrals.show.total')
      end

      it 'returns referral details' do
        get "/mobile/v0/referrals/#{encrypted_id}", headers: sis_headers

        expect(response).to have_http_status(:ok)
        assert_schema_conform(200)

        json = response.parsed_body
        expect(json['data']['type']).to eq('referrals')
        expect(json['data']['attributes']).to have_key('categoryOfCare')
        expect(json['data']['attributes']).to have_key('provider')
        expect(json['data']['attributes']).to have_key('referringFacility')
        expect(json['data']['attributes']).to have_key('appointments')
        expect(json['data']['attributes']['onlineSchedule']).to be true
      end

      it 'sets has_appointments to false when there are no active appointments' do
        get "/mobile/v0/referrals/#{encrypted_id}", headers: sis_headers

        json = response.parsed_body
        expect(json['data']['attributes']['hasAppointments']).to be false
      end

      context 'when there are active appointments' do
        let(:active_appointments) do
          {
            EPS: { data: [{ id: 'appt-1', status: 'active', start: '2025-06-01T09:00:00Z' }] },
            VAOS: { data: [] }
          }
        end

        before do
          allow(appointments_service_double).to receive(:get_active_appointments_for_referral)
            .and_return(active_appointments)
        end

        it 'sets has_appointments to true' do
          get "/mobile/v0/referrals/#{encrypted_id}", headers: sis_headers

          json = response.parsed_body
          expect(json['data']['attributes']['hasAppointments']).to be true
        end
      end

      context 'when the service raises an error' do
        before do
          allow(referral_service_double).to receive(:get_referral).and_raise(StandardError, 'service error')
        end

        it 'increments the failure counter' do
          expect { get "/mobile/v0/referrals/#{encrypted_id}", headers: sis_headers }
            .to trigger_statsd_increment('mobile.referrals.show.failure')
        end
      end
    end
  end
end
