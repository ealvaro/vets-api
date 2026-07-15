# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'VAOS::V2::UnifiedSlots', :skip_mvi, type: :request do
  let(:measure_yields) { ->(*_args, **_kwargs, &block) { block&.call } }
  let(:current_user) { build(:user, :vaos) }
  let(:headers) { { 'Content-Type' => 'application/json', 'Accept' => 'application/json' } }
  let(:mock_referral_service) { instance_double(Ccra::ReferralService) }
  let(:mock_eps_draft_service) { instance_double(VAOS::V2::Unified::EpsDraftService) }
  let(:mock_eps_provider_service) { instance_double(Eps::ProviderService) }
  let(:mock_referral) do
    OpenStruct.new(
      referral_number: 'VA0000005678',
      referral_date: '2026-04-01',
      expiration_date: '2026-06-01',
      category_of_care: 'optometry'
    )
  end
  let(:draft_id) { 'draft-abc' }
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

  before do
    allow(Settings.mhv).to receive(:facility_range).and_return([[1, 999]])
    sign_in_as(current_user)
    allow_any_instance_of(VAOS::UserService).to receive(:session).and_return('stubbed_token')
    allow(Rails.logger).to receive(:info)
    allow(Rails.logger).to receive(:error)
    allow(Rails.logger).to receive(:warn)
    allow(StatsD).to receive(:increment)
    allow(StatsD).to receive(:measure, &measure_yields)

    allow(VAOS::ReferralEncryptionService).to receive(:decrypt).with('encrypted-ref-id').and_return('consult-123')
    allow(Ccra::ReferralService).to receive(:new).and_return(mock_referral_service)
    allow(mock_referral_service).to receive(:get_referral).and_return(mock_referral)
  end

  describe 'GET /vaos/v2/provider_slots' do
    context 'with eps provider type' do
      before do
        allow(VAOS::V2::Unified::EpsDraftService).to receive(:new).and_return(mock_eps_draft_service)
        allow(mock_eps_draft_service).to receive(:create_for_referral).and_return(draft_id)
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
        Timecop.freeze(DateTime.new(2026, 4, 15).utc) do
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
      end

      # The slots endpoint delegates draft creation to
      # {VAOS::V2::Unified::EpsDraftService}, which (a) verifies the referral
      # hasn't already been used, (b) mints a Wellhive draft, and (c) caches
      # its id under +(user_uuid, referral_number)+ so the booking endpoint
      # can resume it at submit time. The orchestrator's behavior is
      # unit-tested in +eps_draft_service_spec.rb+; this test just confirms
      # the controller delegates instead of touching EPS or Redis directly.
      it 'delegates draft creation to EpsDraftService with the referral' do
        get('/vaos/v2/provider_slots', params: base_params, headers:)

        expect(mock_eps_draft_service).to have_received(:create_for_referral) do |arg|
          expect(arg.referral_number).to eq('VA0000005678')
        end
      end

      it 'passes the draft ID to get_provider_slots' do
        get('/vaos/v2/provider_slots', params: base_params, headers:)

        expect(mock_eps_provider_service).to have_received(:get_provider_slots)
          .with('prov-789', hash_including(appointmentId: 'draft-abc'))
      end

      it 'uses referral dates for the slot window' do
        Timecop.freeze(Time.zone.parse('2026-03-15T00:00:00Z')) do
          get('/vaos/v2/provider_slots', params: base_params, headers:)

          expect(mock_eps_provider_service).to have_received(:get_provider_slots)
            .with('prov-789', hash_including(
                                startOnOrAfter: a_string_matching(/2026-04-/),
                                startBefore: a_string_matching(/2026-06-01/)
                              ))
        end
      end

      it 'passes appointment_type_id from params to slot lookup' do
        get('/vaos/v2/provider_slots', params: base_params, headers:)

        expect(mock_eps_provider_service).to have_received(:get_provider_slots)
          .with('prov-789', hash_including(appointmentTypeId: 'ov'))
      end

      it 'increments index.success and draft_created tagged provider_type:eps' do
        get('/vaos/v2/provider_slots', params: base_params, headers:)

        expect(StatsD).to have_received(:increment)
          .with('api.vaos.unified_slots.index.success', tags: ['provider_type:eps'])
        expect(StatsD).to have_received(:increment)
          .with('api.vaos.unified_slots.draft_created', tags: ['provider_type:eps'])
      end

      it 'records index duration with provider_type tag' do
        get('/vaos/v2/provider_slots', params: base_params, headers:)

        expect(StatsD).to have_received(:measure)
          .with('api.vaos.unified_slots.index.duration', tags: ['provider_type:eps'])
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
          allow(mock_eps_draft_service).to receive(:create_for_referral)
            .and_raise(Common::Exceptions::BackendServiceException.new('VAOS_502'))
        end

        it 'returns a 502 error response' do
          get('/vaos/v2/provider_slots', params: base_params, headers:)

          expect(response).to have_http_status(:bad_gateway)
        end

        it 'increments index.failure tagged provider_type:eps' do
          get('/vaos/v2/provider_slots', params: base_params, headers:)

          expect(StatsD).to have_received(:increment)
            .with(
              'api.vaos.unified_slots.index.failure',
              tags: ['provider_type:eps', 'error_type:backend_service_exception']
            )
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
        allow(VAOS::V2::Unified::EpsDraftService).to receive(:new).and_return(mock_eps_draft_service)

        get('/vaos/v2/provider_slots', params: base_params, headers:)

        expect(data_for(response)['attributes']['draftAppointmentId']).to be_nil
        expect(VAOS::V2::Unified::EpsDraftService).not_to have_received(:new)
      end

      it 'does not call EPS provider service' do
        allow(Eps::ProviderService).to receive(:new).and_return(mock_eps_provider_service)

        get('/vaos/v2/provider_slots', params: base_params, headers:)

        expect(Eps::ProviderService).not_to have_received(:new)
      end

      it 'fetches slots from VAOS SystemsService for a VistA station (no clinical_service forwarded)' do
        # Default base_params has no facility_type, which the slots service treats as non-Cerner.
        # VPG rejects clinicalService for VistA stations, so we drop it before the upstream call.
        get('/vaos/v2/provider_slots', params: base_params, headers:)

        expect(mock_systems_service).to have_received(:get_available_slots)
          .with(hash_including(
                  location_id: '983',
                  clinic_id: '455',
                  clinical_service: nil
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

      context 'at a Cerner / Oracle Health facility' do
        let(:cerner_params) { base_params.merge(facility_type: 'va_cerner_facility') }

        it 'forwards clinical_service through to SystemsService' do
          get('/vaos/v2/provider_slots',
              params: cerner_params.merge(clinical_service: 'audiology'),
              headers:)

          expect(response).to have_http_status(:ok)
          expect(mock_systems_service).to have_received(:get_available_slots).with(
            hash_including(clinical_service: 'audiology')
          )
        end

        it 'returns 400 when clinical_service is missing' do
          get('/vaos/v2/provider_slots', params: cerner_params.except(:clinical_service), headers:)

          expect(response).to have_http_status(:bad_request)
        end

        it 'returns 400 when clinical_service is blank' do
          get('/vaos/v2/provider_slots', params: cerner_params.merge(clinical_service: ''), headers:)

          expect(response).to have_http_status(:bad_request)
        end
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

      it 'tags invalid provider_type metrics as unknown' do
        get('/vaos/v2/provider_slots',
            params: { referral_id: 'encrypted-ref-id', provider_service_id: 'prov-789',
                      provider_type: 'invalid' },
            headers:)

        expect(StatsD).to have_received(:measure)
          .with('api.vaos.unified_slots.index.duration', tags: ['provider_type:unknown'])
        expect(StatsD).to have_received(:increment)
          .with(
            'api.vaos.unified_slots.index.failure',
            tags: ['provider_type:unknown', 'error_type:invalid_field_value']
          )
      end
    end

    context 'pilot station allowlist (VA path)' do
      let(:mock_systems_service) { instance_double(VAOS::V2::SystemsService) }

      let(:base_params) do
        { referral_id: 'encrypted-ref-id', provider_type: 'va',
          clinic_id: '455', location_id: '983', clinical_service: 'optometry' }
      end

      before do
        allow(VAOS::V2::SystemsService).to receive(:new).and_return(mock_systems_service)
        allow(mock_systems_service).to receive(:get_available_slots).and_return([])
      end

      def stub_allowlist(value)
        allow(Settings.vaos.unified_scheduling)
          .to receive(:allowed_parent_stations).and_return(value)
      end

      it 'returns 404 for a non-allowlisted parent station' do
        stub_allowlist('442')

        get('/vaos/v2/provider_slots', params: base_params, headers:)

        expect(response).to have_http_status(:not_found)
        expect(mock_systems_service).not_to have_received(:get_available_slots)
      end

      it 'allows an allowlisted parent station' do
        stub_allowlist('983')

        get('/vaos/v2/provider_slots', params: base_params, headers:)

        expect(response).to have_http_status(:ok)
      end

      it 'allows a satellite that rolls up to the parent' do
        stub_allowlist('983')

        get('/vaos/v2/provider_slots',
            params: base_params.merge(location_id: '983GC'), headers:)

        expect(response).to have_http_status(:ok)
      end

      it 'allows any station when the allowlist is unset (default)' do
        stub_allowlist(nil)

        get('/vaos/v2/provider_slots',
            params: base_params.merge(location_id: '552'), headers:)

        expect(response).to have_http_status(:ok)
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
