# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'VAOS::V2::UnifiedSlots', :skip_mvi, type: :request do
  before do
    allow(Settings.mhv).to receive(:facility_range).and_return([[1, 999]])
    sign_in_as(current_user)
    allow_any_instance_of(VAOS::UserService).to receive(:session).and_return('stubbed_token')
    allow(Rails.logger).to receive(:info)
    allow(Rails.logger).to receive(:error)
    allow(Rails.logger).to receive(:warn)
    allow(StatsD).to receive(:increment)

    allow(VAOS::ReferralEncryptionService).to receive(:decrypt).with('encrypted-ref-id').and_return('consult-123')
    allow(Ccra::ReferralService).to receive(:new).and_return(mock_referral_service)
    allow(mock_referral_service).to receive(:get_referral).and_return(mock_referral)
  end

  let(:current_user) { build(:user, :vaos) }
  let(:headers) { { 'Content-Type' => 'application/json', 'Accept' => 'application/json' } }

  let(:mock_referral_service) { instance_double(Ccra::ReferralService) }
  let(:mock_eps_appt_service) { instance_double(Eps::AppointmentService) }
  let(:mock_eps_provider_service) { instance_double(Eps::ProviderService) }

  let(:mock_referral) do
    OpenStruct.new(
      referral_number: 'VA0000005678',
      referral_date: '2026-04-01',
      expiration_date: '2026-06-01',
      category_of_care: 'optometry'
    )
  end

  let(:mock_draft_response) { OpenStruct.new(id: 'draft-abc') }

  let(:mock_eps_slots_response) do
    OpenStruct.new(
      slots: [
        { id: 'slot-1|prov|2026-04-20T10:00:00Z|30m0s', start: '2026-04-20T10:00:00Z',
          provider_service_id: 'prov-789' },
        { id: 'slot-2|prov|2026-04-21T14:00:00Z|30m0s', start: '2026-04-21T14:00:00Z',
          provider_service_id: 'prov-789' }
      ]
    )
  end

  describe 'GET /vaos/v2/provider_slots' do
    context 'with eps provider type' do
      before do
        allow(Eps::AppointmentService).to receive(:new).and_return(mock_eps_appt_service)
        allow(mock_eps_appt_service).to receive(:create_draft_appointment).and_return(mock_draft_response)
        allow(Eps::ProviderService).to receive(:new).and_return(mock_eps_provider_service)
        allow(mock_eps_provider_service).to receive(:get_provider_slots).and_return(mock_eps_slots_response)
      end

      let(:base_params) do
        {
          referral_id: 'encrypted-ref-id',
          provider_type: 'eps',
          provider_service_id: 'prov-789',
          appointment_type_id: 'ov',
          network_id: 'sandboxnetwork-5vuTac8v'
        }
      end

      it 'returns slots, draft ID, and provider reference via UnifiedProviderSerializer' do
        get('/vaos/v2/provider_slots', params: base_params, headers:)

        expect(response).to have_http_status(:ok)

        data = data_for(response)
        expect(data['id']).to eq('prov-789')
        expect(data['type']).to eq('provider_slots')

        provider = data['attributes']['provider']
        expect(provider['id']).to eq('prov-789')
        expect(provider['type']).to eq('unified_provider')
        expect(provider['attributes']['providerType']).to eq('eps')
        expect(provider['attributes']['providerServiceId']).to eq('prov-789')
        expect(provider['attributes']['networkId']).to eq('sandboxnetwork-5vuTac8v')

        expect(data['attributes']['draftAppointmentId']).to eq('draft-abc')
        expect(data['attributes']['slots'].length).to eq(2)
      end

      it 'creates a draft appointment using the referral number' do
        get('/vaos/v2/provider_slots', params: base_params, headers:)

        expect(mock_eps_appt_service).to have_received(:create_draft_appointment)
          .with(referral_id: 'VA0000005678')
      end

      it 'passes the draft ID to get_provider_slots' do
        get('/vaos/v2/provider_slots', params: base_params, headers:)

        expect(mock_eps_provider_service).to have_received(:get_provider_slots)
          .with('prov-789', hash_including(appointmentId: 'draft-abc'))
      end

      it 'uses referral dates for the slot window' do
        get('/vaos/v2/provider_slots', params: base_params, headers:)

        expect(mock_eps_provider_service).to have_received(:get_provider_slots)
          .with('prov-789', hash_including(
                              startOnOrAfter: a_string_matching(/2026-04-/),
                              startBefore: a_string_matching(/2026-06-01/)
                            ))
      end

      it 'passes appointment_type_id from params to slot lookup' do
        get('/vaos/v2/provider_slots', params: base_params, headers:)

        expect(mock_eps_provider_service).to have_received(:get_provider_slots)
          .with('prov-789', hash_including(appointmentTypeId: 'ov'))
      end

      it 'returns 400 when provider_service_id is missing' do
        get('/vaos/v2/provider_slots', params: base_params.except(:provider_service_id), headers:)

        expect(response).to have_http_status(:bad_request)
      end

      it 'returns 400 when appointment_type_id is missing' do
        get('/vaos/v2/provider_slots', params: base_params.except(:appointment_type_id), headers:)

        expect(response).to have_http_status(:bad_request)
      end

      context 'when EPS draft creation fails' do
        before do
          allow(mock_eps_appt_service).to receive(:create_draft_appointment)
            .and_raise(Common::Exceptions::BackendServiceException.new('VAOS_502'))
        end

        it 'returns a 502 error response' do
          get('/vaos/v2/provider_slots', params: base_params, headers:)

          expect(response).to have_http_status(:bad_gateway)
        end
      end
    end

    context 'with va provider type' do
      let(:mock_systems_service) { instance_double(VAOS::V2::SystemsService) }

      let(:mock_va_slots) do
        [
          OpenStruct.new(
            id: 'va-slot-1',
            start: '2026-04-20T09:00:00Z',
            end: '2026-04-20T09:30:00Z',
            clinic: { clinic_ien: '455' },
            location: { vha_facility_id: '983' }
          ),
          OpenStruct.new(
            id: 'va-slot-2',
            start: '2026-04-21T10:00:00Z',
            end: '2026-04-21T10:30:00Z',
            clinic: { clinic_ien: '455' },
            location: { vha_facility_id: '983' }
          )
        ]
      end

      let(:base_params) do
        {
          referral_id: 'encrypted-ref-id',
          provider_type: 'va',
          clinic_id: '455',
          location_id: '983',
          clinical_service: 'optometry'
        }
      end

      before do
        allow(VAOS::V2::SystemsService).to receive(:new).and_return(mock_systems_service)
        allow(mock_systems_service).to receive(:get_available_slots).and_return(mock_va_slots)
      end

      it 'returns VA provider details and slots via UnifiedProviderSerializer' do
        get('/vaos/v2/provider_slots', params: base_params, headers:)

        expect(response).to have_http_status(:ok)

        data = data_for(response)
        expect(data['type']).to eq('provider_slots')

        provider = data['attributes']['provider']
        expect(provider['id']).to eq('455')
        expect(provider['type']).to eq('unified_provider')
        expect(provider['attributes']['providerType']).to eq('va')
        expect(provider['attributes']['locationId']).to eq('983')
        expect(provider['attributes']['serviceType']).to eq('optometry')
        expect(data['attributes']['slots'].length).to eq(2)
      end

      it 'does not create a draft appointment' do
        allow(Eps::AppointmentService).to receive(:new).and_return(mock_eps_appt_service)

        get('/vaos/v2/provider_slots', params: base_params, headers:)

        expect(data_for(response)['attributes']['draftAppointmentId']).to be_nil
        expect(Eps::AppointmentService).not_to have_received(:new)
      end

      it 'does not call EPS provider service' do
        allow(Eps::ProviderService).to receive(:new).and_return(mock_eps_provider_service)

        get('/vaos/v2/provider_slots', params: base_params, headers:)

        expect(Eps::ProviderService).not_to have_received(:new)
      end

      it 'fetches slots from VAOS SystemsService' do
        get('/vaos/v2/provider_slots', params: base_params, headers:)

        expect(mock_systems_service).to have_received(:get_available_slots)
          .with(hash_including(
                  location_id: '983',
                  clinic_id: '455',
                  clinical_service: 'optometry'
                ))
      end

      it 'returns 400 when clinic_id is missing' do
        get('/vaos/v2/provider_slots', params: base_params.except(:clinic_id), headers:)

        expect(response).to have_http_status(:bad_request)
      end

      it 'returns 400 when location_id is missing' do
        get('/vaos/v2/provider_slots', params: base_params.except(:location_id), headers:)

        expect(response).to have_http_status(:bad_request)
      end
    end

    context 'with missing or invalid params' do
      it 'returns 400 when referral_id is missing' do
        get('/vaos/v2/provider_slots',
            params: { provider_service_id: 'prov-789', provider_type: 'eps',
                      appointment_type_id: 'ov' }, headers:)

        expect(response).to have_http_status(:bad_request)
      end

      it 'returns 400 when provider_type is missing' do
        get('/vaos/v2/provider_slots',
            params: { referral_id: 'encrypted-ref-id', provider_service_id: 'prov-789' }, headers:)

        expect(response).to have_http_status(:bad_request)
      end

      it 'returns 400 when provider_type is invalid' do
        get('/vaos/v2/provider_slots',
            params: { referral_id: 'encrypted-ref-id', provider_service_id: 'prov-789',
                      provider_type: 'invalid' },
            headers:)

        expect(response).to have_http_status(:bad_request)
      end
    end

    context 'when user is not LOA3' do
      let(:current_user) { build(:user, :loa1) }

      it 'returns 403' do
        get('/vaos/v2/provider_slots',
            params: { referral_id: 'encrypted-ref-id', provider_service_id: 'prov-789',
                      provider_type: 'eps', appointment_type_id: 'ov' },
            headers:)

        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  def data_for(resp)
    JSON.parse(resp.body)['data']
  end
end
