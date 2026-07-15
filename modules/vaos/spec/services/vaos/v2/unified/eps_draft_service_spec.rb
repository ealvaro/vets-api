# frozen_string_literal: true

require 'rails_helper'

RSpec.describe VAOS::V2::Unified::EpsDraftService do
  let(:user) { build(:user, :vaos) }
  let(:referral) { OpenStruct.new(referral_number: 'VA0000007419') }

  let(:appointments_service) { instance_double(VAOS::V2::AppointmentsService) }
  let(:eps_appointment_service) { instance_double(Eps::AppointmentService) }
  let(:service) do
    described_class.new(
      user,
      appointments_service:,
      eps_appointment_service:
    )
  end

  let(:draft_response) { OpenStruct.new(id: 'eps-draft-1', state: 'draft') }

  before do
    allow(PersonalInformationLog).to receive(:create)
    allow(StatsD).to receive(:increment)
  end

  describe '#create_for_referral' do
    context 'when the referral has not been used' do
      before do
        allow(appointments_service).to receive(:referral_appointment_already_exists?)
          .and_return({ exists: false, error: false })
        allow(eps_appointment_service).to receive(:create_resumable_draft_appointment)
          .and_return(draft_response)
      end

      it 'returns the freshly-minted draft id' do
        expect(service.create_for_referral(referral)).to eq('eps-draft-1')
      end

      it 'verifies the referral first, then creates the draft' do
        expect(appointments_service).to receive(:referral_appointment_already_exists?)
          .with('VA0000007419')
          .ordered
          .and_return({ exists: false, error: false })
        expect(eps_appointment_service).to receive(:create_resumable_draft_appointment)
          .with(referral_id: 'VA0000007419')
          .ordered
          .and_return(draft_response)

        service.create_for_referral(referral)
      end

      it 'does not log a PersonalInformationLog entry on the happy path' do
        service.create_for_referral(referral)

        expect(PersonalInformationLog).not_to have_received(:create)
      end
    end

    # Mirrors the legacy EPS draft-creation referral-already-used precheck.
    # Without this branch the unified flow would let a duplicate
    # booking attempt mint a wasted Wellhive draft and surface a generic 4xx
    # at submit time instead of a clean 422 with PII logging.
    context 'when the referral has already been used' do
      before do
        allow(appointments_service).to receive(:referral_appointment_already_exists?)
          .and_return({ exists: true, error: false })
      end

      it 'raises 422 UnprocessableEntity with the legacy error message' do
        expect { service.create_for_referral(referral) }
          .to raise_error(Common::Exceptions::UnprocessableEntity) do |e|
            expect(e.errors.first.detail).to eq('No new appointment created: referral is already used')
          end
      end

      it 'never reaches Wellhive draft creation' do
        expect(eps_appointment_service).not_to receive(:create_resumable_draft_appointment)

        expect { service.create_for_referral(referral) }
          .to raise_error(Common::Exceptions::UnprocessableEntity)
      end

      it 'records a PersonalInformationLog entry tagged eps_draft_referral_already_used' do
        expect(PersonalInformationLog).to receive(:create).with(
          error_class: 'eps_draft_referral_already_used',
          data: hash_including(
            referral_number: 'VA0000007419',
            user_uuid: user.uuid,
            failure_reason: 'Referral is already used for an existing appointment'
          )
        )

        expect { service.create_for_referral(referral) }
          .to raise_error(Common::Exceptions::UnprocessableEntity)
      end

      it 'increments a StatsD counter tagged eps_draft_referral_already_used' do
        expect { service.create_for_referral(referral) }
          .to raise_error(Common::Exceptions::UnprocessableEntity)

        expect(StatsD).to have_received(:increment)
          .with(
            'api.vaos.unified_eps_draft.eps_draft_referral_already_used',
            tags: ['provider_type:eps']
          )
      end
    end

    # Distinct from "already used" so operators can tell upstream availability
    # outages apart from legitimate duplicate-booking attempts. Same severity
    # downstream (502) but different StatsD/PII log signature.
    context 'when the existing-appointment check itself errors' do
      before do
        allow(appointments_service).to receive(:referral_appointment_already_exists?)
          .and_return({ exists: false, error: true, failures: 'Service unavailable' })
      end

      it 'raises 502 with a description of the upstream failure' do
        expect { service.create_for_referral(referral) }
          .to raise_error(Common::Exceptions::BadGateway) do |e|
            expect(e.errors.first.status).to eq('502')
            expect(e.errors.first.detail).to include('Error checking existing appointments')
            expect(e.errors.first.detail).to include('Service unavailable')
          end
      end

      it 'never reaches Wellhive draft creation' do
        expect(eps_appointment_service).not_to receive(:create_resumable_draft_appointment)

        expect { service.create_for_referral(referral) }
          .to raise_error(Common::Exceptions::BadGateway)
      end

      it 'records a PersonalInformationLog entry tagged eps_draft_existing_appointment_check_failed' do
        expect(PersonalInformationLog).to receive(:create).with(
          error_class: 'eps_draft_existing_appointment_check_failed',
          data: hash_including(
            referral_number: 'VA0000007419',
            user_uuid: user.uuid,
            failure_reason: a_string_including('Service unavailable')
          )
        )

        expect { service.create_for_referral(referral) }
          .to raise_error(Common::Exceptions::BadGateway)
      end

      it 'increments a StatsD counter tagged eps_draft_existing_appointment_check_failed' do
        expect { service.create_for_referral(referral) }
          .to raise_error(Common::Exceptions::BadGateway)

        expect(StatsD).to have_received(:increment)
          .with(
            'api.vaos.unified_eps_draft.eps_draft_existing_appointment_check_failed',
            tags: ['provider_type:eps']
          )
      end
    end

    context 'when the EPS draft response is missing an id' do
      before do
        allow(appointments_service).to receive(:referral_appointment_already_exists?)
          .and_return({ exists: false, error: false })
        allow(eps_appointment_service).to receive(:create_resumable_draft_appointment)
          .and_return(OpenStruct.new(state: 'draft'))
      end

      it 'raises 502 (defensive; mirrors the legacy slots-controller behavior)' do
        expect { service.create_for_referral(referral) }
          .to raise_error(Common::Exceptions::BadGateway) do |e|
            expect(e.errors.first.status).to eq('502')
            expect(e.errors.first.detail).to include('EPS draft response missing appointment id')
          end
      end
    end

    context 'when the EPS appointment service raises' do
      before do
        allow(appointments_service).to receive(:referral_appointment_already_exists?)
          .and_return({ exists: false, error: false })
        allow(eps_appointment_service).to receive(:create_resumable_draft_appointment)
          .and_raise(Common::Exceptions::BackendServiceException.new(nil, {}, 502))
      end

      it 'propagates the exception unchanged' do
        expect { service.create_for_referral(referral) }
          .to raise_error(Common::Exceptions::BackendServiceException)
      end
    end
  end

  describe 'default service construction' do
    let(:service) { described_class.new(user) }
    let(:appts_double) { instance_double(VAOS::V2::AppointmentsService) }
    let(:eps_double) { instance_double(Eps::AppointmentService) }

    before do
      allow(VAOS::V2::AppointmentsService).to receive(:new).with(user).and_return(appts_double)
      allow(Eps::AppointmentService).to receive(:new).with(user).and_return(eps_double)
      allow(appts_double).to receive(:referral_appointment_already_exists?)
        .and_return({ exists: false, error: false })
      allow(eps_double).to receive(:create_resumable_draft_appointment).and_return(draft_response)
    end

    it 'lazily constructs both upstream services from the user' do
      service.create_for_referral(referral)

      expect(VAOS::V2::AppointmentsService).to have_received(:new).with(user)
      expect(Eps::AppointmentService).to have_received(:new).with(user)
    end
  end
end
