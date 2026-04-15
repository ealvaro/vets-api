# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AccreditedRepresentativePortal::ClaimantDetailsService do
  subject(:service_call) do
    described_class.new(
      icn:,
      representative_name:,
      benefit_type_param:,
      power_of_attorney_requests:,
      is_representative:
    ).call
  end

  let(:icn) { '1008714701V416111' }
  let(:benefit_type_param) { 'compensation' }
  let(:representative_name) { 'Space Force Cadets' }
  let(:power_of_attorney_requests) { [] }
  let(:is_representative) { false }
  let(:pending_notice_enabled) { false }

  let(:mpi_profile) do
    build(
      :mpi_profile,
      icn:,
      given_names: ['John'],
      family_name: 'Smith',
      birth_date: '1980-01-01',
      ssn: '666-66-6666',
      home_phone: '555-555-5555',
      address: OpenStruct.new(
        street: '123 Main St',
        street2: 'Apt 4',
        city: 'Springfield',
        state: 'VA',
        postal_code: '12345'
      )
    )
  end

  let(:mpi_profile_response) { create(:find_profile_response, profile: mpi_profile) }

  let(:mpi_service) { instance_double(MPI::Service) }
  let(:itf_service) { instance_double(BenefitsClaims::Service) }

  let(:mpi_address) do
    OpenStruct.new(
      street: '123 Main St',
      street2: 'Apt 4',
      city: 'Springfield',
      state: 'VA',
      postal_code: '12345'
    )
  end

  before do
    allow(Flipper).to receive(:enabled?)
      .with(:accredited_representative_portal_cd_pending_notice)
      .and_return(pending_notice_enabled)
    allow(MPI::Service).to receive(:new).and_return(mpi_service)
    allow(mpi_service).to receive(:find_profile_by_identifier).and_return(mpi_profile_response)

    allow(BenefitsClaims::Service).to receive(:new).with(icn).and_return(itf_service)

    allow(mpi_profile).to receive(:address).and_return(mpi_address)
  end

  describe '#call' do
    context 'when MPI returns a profile and ITF lookup succeeds' do
      before do
        allow(BenefitsClaims::Service).to receive(:new).with(icn).and_return(itf_service)
        allow(itf_service).to receive(:get_intent_to_file).with('compensation').and_return({ 'status' => 'ok' })
      end

      it 'returns payload with claimant profile fields (SSN masked to last 4)' do
        FactoryBot.rewind_sequences
        payload = service_call

        expect(payload).to be_a(Hash)
        data = payload.fetch(:data)

        expect(data[:first_name]).to eq('John')
        expect(data[:last_name]).to eq('Smith')
        expect(data[:birth_date]).to eq('1980-01-01')
        expect(data[:ssn]).to eq('6666')
        expect(data[:phone]).to eq('555-555-5555')

        expect(data[:address]).to eq(
          line1: '123 Main St',
          line2: 'Apt 4',
          city: 'Springfield',
          state: 'VA',
          zip: '12345'
        )
        expect(data[:representative_name]).to eq('Space Force Cadets')
        expect(data).not_to have_key(:is_representative)
        expect(data).not_to have_key(:poa_requests)
        expect(data[:email]).to eq('person100@example.com')
      end

      it 'returns itf as an array' do
        payload = service_call
        expect(payload.dig(:data, :itf)).to eq([{ 'status' => 'ok' }])
      end

      context 'when there are pending poa requests' do
        let(:pending_notice_enabled) { true }
        let(:is_representative) { true }
        let(:resolution) { double(blank?: false) }
        let(:request_with_resolution) do
          double(
            id: 123,
            resolution:,
            created_at: Time.zone.parse('2024-01-01 00:00:00')
          )
        end
        let(:request_without_resolution) do
          double(
            id: 456,
            resolution: nil,
            created_at: Time.zone.parse('2024-01-02 00:00:00')
          )
        end
        let(:power_of_attorney_requests) { [request_with_resolution, request_without_resolution] }
        let(:serializer_class) do
          Class.new do
            def initialize(*); end

            def serializable_hash
              {
                resolution: {
                  type: 'decision',
                  decisionType: 'acceptance'
                }
              }
            end
          end
        end

        before do
          stub_const('AccreditedRepresentativePortal::PowerOfAttorneyRequestSerializer', serializer_class)
        end

        it 'includes serialized poa requests and representative flag' do
          payload = service_call
          data = payload.fetch(:data)

          expect(data[:is_representative]).to be(true)
          expect(data[:poa_requests]).to eq(
            [
              {
                id: 123,
                resolution: {
                  type: 'decision',
                  decisionType: 'acceptance'
                }
              },
              {
                id: 456,
                resolution: nil
              }
            ]
          )
        end
      end

      context 'when there are pending poa requests but the feature flag is off' do
        let(:pending_notice_enabled) { false }
        let(:is_representative) { true }
        let(:resolution) { double(blank?: false) }
        let(:request_with_resolution) do
          double(
            id: 123,
            resolution:,
            created_at: Time.zone.parse('2024-01-01 00:00:00')
          )
        end
        let(:power_of_attorney_requests) { [request_with_resolution] }

        it 'does not include representative or poa_requests in the payload' do
          payload = service_call
          data = payload.fetch(:data)

          expect(data).not_to have_key(:is_representative)
          expect(data).not_to have_key(:poa_requests)
        end
      end

      context 'VA profile returns errors' do
        let(:logger) { double }

        before do
          allow(VAProfile::ContactInformation::V2::Service).to receive(:get_person).and_raise(
            Common::Exceptions::BackendServiceException
          )
          allow(Rails).to receive(:logger).and_return logger
        end

        it 'logs the error and returns an empty email' do
          expect(logger).to receive(:error).with(
            'ARP: Claimant Details - Unable to fetch claimant email from VA Profile. ' \
            'Common::Exceptions::BackendServiceException'
          )
          payload = service_call
          data = payload.fetch(:data)
          expect(data[:first_name]).to eq('John')
          expect(data[:last_name]).to eq('Smith')
          expect(data[:email]).to be_nil
        end
      end
    end

    context 'when benefit_type_param is nil' do
      let(:benefit_type_param) { nil }

      let(:itf_service_comp) { instance_double(BenefitsClaims::Service) }
      let(:itf_service_pension) { instance_double(BenefitsClaims::Service) }
      let(:itf_service_survivor) { instance_double(BenefitsClaims::Service) }

      before do
        allow(BenefitsClaims::Service).to receive(:new).with(icn).and_return(
          itf_service_comp,
          itf_service_pension,
          itf_service_survivor
        )

        allow(itf_service_comp).to receive(:get_intent_to_file).with('compensation').and_return({ 'type' => 'comp' })
        allow(itf_service_pension).to receive(:get_intent_to_file).with('pension').and_return({ 'type' => 'pension' })
        allow(itf_service_survivor)
          .to receive(:get_intent_to_file)
          .with('survivor')
          .and_return({ 'type' => 'survivor' })
      end

      it 'requests all supported ITF types and returns them as an array' do
        payload = service_call

        expect(BenefitsClaims::Service).to have_received(:new).with(icn).exactly(3).times

        expect(itf_service_comp).to have_received(:get_intent_to_file).with('compensation')
        expect(itf_service_pension).to have_received(:get_intent_to_file).with('pension')
        expect(itf_service_survivor).to have_received(:get_intent_to_file).with('survivor')

        itfs = payload.dig(:data, :itf)
        expect(itfs).to contain_exactly(
          { 'type' => 'comp' },
          { 'type' => 'pension' },
          { 'type' => 'survivor' }
        )
      end

      it 'still masks SSN to last 4 digits' do
        allow(itf_service_comp).to receive(:get_intent_to_file).with('compensation').and_return({ 'type' => 'comp' })
        allow(itf_service_pension).to receive(:get_intent_to_file).with('pension').and_return({ 'type' => 'pension' })
        allow(itf_service_survivor)
          .to receive(:get_intent_to_file)
          .with('survivor')
          .and_return({ 'type' => 'survivor' })

        payload = service_call
        expect(payload.dig(:data, :ssn)).to eq('6666')
      end
    end

    context 'when ITF lookup raises' do
      let(:itf_service_raising) { instance_double(BenefitsClaims::Service) }

      before do
        allow(BenefitsClaims::Service).to receive(:new).with(icn).and_return(itf_service_raising)
        allow(itf_service_raising).to receive(:get_intent_to_file).with('compensation').and_raise(StandardError,
                                                                                                  'itf down')
      end

      it 'logs and returns an empty itf array' do
        expect(Rails.logger).to receive(:warn).with(
          'ClaimantDetailsService ITF lookup failed',
          hash_including(
            benefit_type: 'compensation',
            error: 'StandardError'
          )
        )

        payload = service_call
        expect(payload.dig(:data, :itf)).to eq([])
      end

      it 'still returns masked SSN in payload' do
        allow(Rails.logger).to receive(:warn)
        payload = service_call
        expect(payload.dig(:data, :ssn)).to eq('6666')
      end
    end

    context 'when MPI returns no profile' do
      before do
        allow(mpi_service).to receive(:find_profile_by_identifier).and_return(OpenStruct.new(profile: nil))
      end

      it 'raises RecordNotFound' do
        expect { service_call }.to raise_error(Common::Exceptions::RecordNotFound)
      end
    end
  end
end
