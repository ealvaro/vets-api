# frozen_string_literal: true

require 'rails_helper'

RSpec.describe VAOS::V2::ProvidersController, type: :request do
  describe 'GET /vaos/v2/providers (index)' do
    let(:referral_id) { 'encrypted-referral-id' }
    let(:decrypted_id) { '984_646907' }

    let(:referral) do
      double(
        'Ccra::ReferralDetail',
        category_of_care: 'UROLOGY',
        provider_npi: '91560381x',
        referral_number: 'VA0000007241'
      )
    end

    let(:va_provider) do
      VAOS::V2::Unified::VAProvider.new(
        id: '455',
        location_id: '983',
        facility_name: 'Cheyenne VA Medical Center',
        name: 'CHY UROLOGY',
        address: { street1: '2360 E Pershing Blvd', city: 'Cheyenne', state: 'WY', zip: '82001' },
        phone: '307-778-7550',
        latitude: 41.1456,
        longitude: -104.7892,
        distance_from_user: 3.2
      )
    end

    let(:eps_provider) do
      VAOS::V2::Unified::EpsProvider.new(
        id: '9mN718pH',
        name: 'Dr. Bones @ Melbourne Medical',
        address: { street1: '1105 Palmetto Ave', city: 'Melbourne', state: 'FL', zip: '32901' },
        phone: '555-555-0001',
        latitude: 28.08061,
        longitude: -80.60322,
        npi: '91560381x',
        distance_from_user: 2.1
      )
    end

    context 'when called without authorization' do
      it 'returns unauthorized' do
        get '/vaos/v2/providers', params: { referral_id: }

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when called with valid params' do
      before do
        sign_in_as(create(:user, :loa3))

        allow(VAOS::ReferralEncryptionService).to receive(:decrypt)
          .with(referral_id).and_return(decrypted_id)

        referral_service = instance_double(Ccra::ReferralService)
        allow(Ccra::ReferralService).to receive(:new).and_return(referral_service)
        allow(referral_service).to receive(:get_referral).and_return(referral)

        search_service = instance_double(VAOS::V2::Unified::ProviderSearchService)
        allow(VAOS::V2::Unified::ProviderSearchService).to receive(:new).and_return(search_service)
        allow(search_service).to receive(:search).and_return([eps_provider, va_provider])
      end

      it 'returns a combined provider list' do
        get '/vaos/v2/providers', params: { referral_id: }

        expect(response).to have_http_status(:ok)
        body = JSON.parse(response.body)
        expect(body['data'].size).to eq(2)
      end

      it 'includes provider_type flags' do
        get '/vaos/v2/providers', params: { referral_id: }

        body = JSON.parse(response.body)
        types = body['data'].map { |p| p['attributes']['providerType'] }
        expect(types).to contain_exactly('eps', 'va')
      end

      it 'marks the referral provider with isReferralProvider' do
        get '/vaos/v2/providers', params: { referral_id: }

        body = JSON.parse(response.body)
        referral_provider = body['data'].find { |p| p['attributes']['isReferralProvider'] }
        expect(referral_provider).to be_present
        expect(referral_provider['id']).to eq('9mN718pH')
      end

      it 'passes radius parameter to the search service' do
        search_service = VAOS::V2::Unified::ProviderSearchService.new(nil)
        allow(VAOS::V2::Unified::ProviderSearchService).to receive(:new).and_return(search_service)
        allow(search_service).to receive(:search).and_return([])

        get '/vaos/v2/providers', params: { referral_id:, radius: '30' }

        expect(search_service).to have_received(:search).with(
          referral: anything,
          radius: 30
        )
      end

      it 'falls back to default radius for non-numeric radius' do
        search_service = VAOS::V2::Unified::ProviderSearchService.new(nil)
        allow(VAOS::V2::Unified::ProviderSearchService).to receive(:new).and_return(search_service)
        allow(search_service).to receive(:search).and_return([])

        get '/vaos/v2/providers', params: { referral_id:, radius: 'abc' }

        expect(search_service).to have_received(:search).with(
          referral: anything,
          radius: 25
        )
      end

      it 'falls back to default radius for non-positive radius' do
        search_service = VAOS::V2::Unified::ProviderSearchService.new(nil)
        allow(VAOS::V2::Unified::ProviderSearchService).to receive(:new).and_return(search_service)
        allow(search_service).to receive(:search).and_return([])

        get '/vaos/v2/providers', params: { referral_id:, radius: '-5' }

        expect(search_service).to have_received(:search).with(
          referral: anything,
          radius: 25
        )
      end

      it 'returns proper unified_provider type for each entry' do
        get '/vaos/v2/providers', params: { referral_id: }

        body = JSON.parse(response.body)
        types = body['data'].map { |p| p['type'] }
        expect(types).to all(eq('unified_provider'))
      end

      context 'onlineScheduling indicator (post-MVP flag)' do
        it 'omits onlineScheduling when the flag is disabled' do
          allow(Flipper).to receive(:enabled?).and_call_original
          allow(Flipper).to receive(:enabled?)
            .with(:va_online_scheduling_cc_direct_scheduling_v2_post_mvp, anything).and_return(false)

          get '/vaos/v2/providers', params: { referral_id: }

          body = JSON.parse(response.body)
          expect(body['data']).to all(satisfy { |p| !p['attributes'].key?('onlineScheduling') })
        end

        it 'includes onlineScheduling when the flag is enabled' do
          allow(Flipper).to receive(:enabled?).and_call_original
          allow(Flipper).to receive(:enabled?)
            .with(:va_online_scheduling_cc_direct_scheduling_v2_post_mvp, anything).and_return(true)

          get '/vaos/v2/providers', params: { referral_id: }

          body = JSON.parse(response.body)
          expect(body['data']).to all(satisfy { |p| p['attributes'].key?('onlineScheduling') })
        end
      end
    end

    context 'when referral_id is missing' do
      before { sign_in_as(create(:user, :loa3)) }

      it 'returns bad request' do
        get '/vaos/v2/providers'

        expect(response).to have_http_status(:bad_request)
      end
    end
  end
end
