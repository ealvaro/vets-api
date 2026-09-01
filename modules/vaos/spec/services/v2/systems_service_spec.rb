# frozen_string_literal: true

require 'rails_helper'

describe VAOS::V2::SystemsService do
  subject { VAOS::V2::SystemsService.new(user) }

  let(:user) { build(:user, :vaos) }

  before do
    allow_any_instance_of(VAOS::UserService).to receive(:session).and_return('stubbed_token')
    allow(Flipper).to receive(:enabled?).with(:va_online_scheduling_vaos_alternate_route).and_return(false)
  end

  describe '#get_facility_clinics' do
    context 'using VAOS' do
      before do
        allow(Flipper).to receive(:enabled?).with(:va_online_scheduling_use_vpg, user).and_return(false)
      end

      context 'with 7 clinics, some ineligible for patient direct scheduling' do
        it 'returns only the clinics eligible for patient direct scheduling' do
          VCR.use_cassette('vaos/v2/systems/get_facility_clinics_200', match_requests_on: %i[method path query]) do
            response = subject.get_facility_clinics(location_id: '983', clinical_service: 'audiology')
            expect(response.size).to eq(3)
            expect(response.map(&:id)).to eq(%w[945 1014 1020])
          end
        end

        it 'logs the filtered out clinic ids and their patient_direct_scheduling values' do
          VCR.use_cassette('vaos/v2/systems/get_facility_clinics_200', match_requests_on: %i[method path query]) do
            allow(Rails.logger).to receive(:info)
            expect(Rails.logger).to receive(:info).with(
              'VAOS::V2::SystemsService#get_facility_clinics, clinics filtered out due to patient_direct_scheduling',
              { location_id: '983', clinical_service: 'audiology',
                filtered_clinics: [
                  { id: '570', patient_direct_scheduling: false },
                  { id: '947', patient_direct_scheduling: nil },
                  { id: '1022', patient_direct_scheduling: nil },
                  { id: '1072', patient_direct_scheduling: nil }
                ] }
            )
            subject.get_facility_clinics(location_id: '983', clinical_service: 'audiology')
          end
        end

        context 'when clinic_ids is specified' do
          it 'returns all requested clinics, skipping the patient direct scheduling filter' do
            VCR.use_cassette('vaos/v2/systems/get_facility_clinics_200', match_requests_on: %i[method path query]) do
              response = subject.get_facility_clinics(location_id: '983', clinic_ids: '570,945')
              expect(response.map(&:id)).to eq(%w[570 945])
            end
          end

          it 'does not log filtered clinics' do
            VCR.use_cassette('vaos/v2/systems/get_facility_clinics_200', match_requests_on: %i[method path query]) do
              expect(Rails.logger).not_to receive(:info).with(
                'VAOS::V2::SystemsService#get_facility_clinics, clinics filtered out due to patient_direct_scheduling',
                anything
              )
              subject.get_facility_clinics(location_id: '983', clinic_ids: '570,945')
            end
          end
        end

        context 'when the upstream server returns a 400' do
          it 'raises a backend exception' do
            VCR.use_cassette('vaos/v2/systems/get_facility_clinics_400', match_requests_on: %i[method path query]) do
              expect do
                subject.get_facility_clinics(location_id: '983', clinic_ids: '570', clinical_service: 'audiology')
              end.to raise_error(Common::Exceptions::BackendServiceException, /VAOS_400/)
            end
          end
        end
      end
    end

    context 'using VPG' do
      before do
        allow(Flipper).to receive(:enabled?).with(:va_online_scheduling_use_vpg, user).and_return(true)
      end

      context 'with 7 clinics, some ineligible for patient direct scheduling' do
        it 'returns only the clinics eligible for patient direct scheduling' do
          VCR.use_cassette('vaos/v2/systems/get_facility_clinics_200_vpg', match_requests_on: %i[method path query]) do
            response = subject.get_facility_clinics(location_id: '983', clinical_service: 'audiology')
            expect(response.size).to eq(3)
            expect(response.map(&:id)).to eq(%w[945 1014 1020])
          end
        end
      end

      context 'when the upstream server returns a 400' do
        before do
          allow(Flipper).to receive(:enabled?).with(:va_online_scheduling_use_vpg, user).and_return(false)
        end

        it 'raises a backend exception' do
          VCR.use_cassette('vaos/v2/systems/get_facility_clinics_400', match_requests_on: %i[method path query]) do
            expect do
              subject.get_facility_clinics(location_id: '983', clinic_ids: '570', clinical_service: 'audiology')
            end.to raise_error(Common::Exceptions::BackendServiceException, /VAOS_400/)
          end
        end
      end
    end
  end

  describe '#get_available_slots' do
    context 'using VAOS' do
      before do
        allow(Flipper).to receive(:enabled?).with(:va_online_scheduling_use_vpg, user).and_return(false)
      end

      context 'when the upstream server returns status code 500' do
        it 'raises a backend exception' do
          VCR.use_cassette('vaos/v2/systems/get_available_slots_500', match_requests_on: %i[method path query]) do
            expect do
              subject.get_available_slots({ location_id: '983',
                                            clinic_id: '1081',
                                            start_dt: '2021-10-01T00:00:00Z',
                                            end_dt: '2021-12-31T23:59:59Z' })
            end.to raise_error(Common::Exceptions::BackendServiceException, /VAOS_502/)
          end
        end
      end

      context 'when the upstream server returns status code 200' do
        it 'returns a list of available slots' do
          VCR.use_cassette('vaos/v2/systems/get_available_slots_200', match_requests_on: %i[method path query]) do
            available_slots = subject.get_available_slots({ location_id: '983',
                                                            clinic_id: '1081',
                                                            start_dt: '2021-10-26T00:00:00Z',
                                                            end_dt: '2021-12-30T23:59:59Z' })
            expect(available_slots.size).to eq(730)
            expect(available_slots[400].id).to eq('3230323131323031323130303A323032313132303132313330')
            expect(available_slots[400].start).to eq('2021-12-01T21:00:00Z')
            expect(available_slots[400].end).to eq('2021-12-01T21:30:00Z')
          end
        end
      end
    end
  end

  describe '#get_next_available_slots' do
    context 'when the upstream server returns status code 200' do
      it 'returns next available slots for the requested clinics' do
        stub_request(:get, %r{/vpg/v1/next-available-slot})
          .with(
            query: hash_including(
              'site' => '983',
              'before' => '2026-04-30T23:59:59Z',
              'onOrAfter' => '2026-04-08T00:00:00Z',
              'clinic' => '570,945'
            )
          )
          .to_return(
            status: 200,
            body: {
              data: [
                {
                  ien: '570',
                  status: 'success',
                  hasAvailability: true,
                  slotId: 'abc123',
                  start: '2026-04-10T10:00:00Z',
                  end: '2026-04-10T10:30:00Z'
                },
                {
                  ien: '945',
                  status: 'failure'
                }
              ]
            }.to_json,
            headers: { 'Content-Type' => 'application/json' }
          )
        response = subject.get_next_available_slots({
                                                      location_id: '983',
                                                      clinic_ids: %w[570 945],
                                                      on_or_after: '2026-04-08T00:00:00Z',
                                                      before: '2026-04-30T23:59:59Z'
                                                    })

        expect(response).to be_present
        expect(response.size).to eq(2)

        expect(response[0].id).to eq('570')
        expect(response[0].clinic_id).to eq('570')
        expect(response[0].status).to eq('success')
        expect(response[0].has_availability).to be(true)
        expect(response[0].slot_id).to eq('abc123')
        expect(response[0].start).to eq('2026-04-10T10:00:00Z')
        expect(response[0].end).to eq('2026-04-10T10:30:00Z')

        expect(response[1].id).to eq('945')
        expect(response[1].clinic_id).to eq('945')
        expect(response[1].status).to eq('failure')
      end
    end

    context 'when the upstream server returns status code 400' do
      it 'raises a backend exception' do
        stub_request(:get, %r{/vpg/v1/next-available-slot})
          .to_return(
            status: 400,
            body: {
              errors: [
                {
                  detail: 'Bad request'
                }
              ]
            }.to_json,
            headers: { 'Content-Type' => 'application/json' }
          )

        expect do
          subject.get_next_available_slots({
                                             location_id: '983',
                                             clinic_ids: %w[570 945],
                                             before: '2026-04-30T23:59:59Z'
                                           })
        end.to raise_error(Common::Exceptions::BackendServiceException)
      end
    end

    context 'when clinic_ids is passed as a csv string' do
      it 'handles the clinic list correctly' do
        stub_request(:get, %r{/vpg/v1/next-available-slot})
          .to_return(
            status: 200,
            body: {
              data: [
                { ien: '570', status: 'success' },
                { ien: '945', status: 'failure' }
              ]
            }.to_json,
            headers: { 'Content-Type' => 'application/json' }
          )

        response = subject.get_next_available_slots({
                                                      location_id: '983',
                                                      clinic_ids: '570,945',
                                                      before: '2026-04-30T23:59:59Z'
                                                    })

        expect(response).to be_present
      end
    end

    context 'when on_or_after is not provided' do
      it 'calls the endpoint without onOrAfter' do
        stub_request(:get, %r{/vpg/v1/next-available-slot})
          .with(query: hash_including(
            'site' => '983',
            'before' => '2026-04-30T23:59:59Z'
          ))
          .to_return(
            status: 200,
            body: { data: [] }.to_json,
            headers: { 'Content-Type' => 'application/json' }
          )

        response = subject.get_next_available_slots({
                                                      location_id: '983',
                                                      clinic_ids: %w[570 945],
                                                      before: '2026-04-30T23:59:59Z'
                                                    })

        expect(response).to eq([])
      end
    end
  end
end
