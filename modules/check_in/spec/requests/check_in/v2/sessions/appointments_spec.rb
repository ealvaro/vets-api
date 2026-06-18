# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'CheckIn::V2::Sessions::Appointments', type: :request do
  let(:id) { 'd602d9eb-9a31-484f-9637-13ab0b507e0d' }
  let(:memory_store) { ActiveSupport::Cache.lookup_store(:memory_store) }

  before do
    allow(Rails).to receive(:cache).and_return(memory_store)
    allow(Flipper).to receive(:enabled?).with('check_in_experience_enabled').and_return(true)
    allow(Flipper).to receive(:enabled?).with('check_in_experience_mock_enabled').and_return(false)

    allow(Flipper).to receive(:enabled?).with(:check_in_experience_upcoming_appointments_enabled).and_return(true)
    allow(Flipper).to receive(:enabled?)
      .with(:check_in_experience_va_mobile_facilities_v3_enabled)
      .and_return(false)
    allow(Flipper).to receive(:enabled?)
      .with(:check_in_experience_vds_site_info_clinics_enabled)
      .and_return(false)

    Rails.cache.clear
  end

  describe 'GET `index`' do
    context 'when feature flag is off' do
      before do
        allow(Flipper).to receive(:enabled?).with(:check_in_experience_upcoming_appointments_enabled).and_return(false)
      end

      it 'returns not found' do
        get "/check_in/v2/sessions/#{id}/appointments"

        expect(response).to have_http_status(:not_found)
      end
    end

    context 'when session does not exist' do
      let(:resp) do
        {
          permissions: 'read.none',
          status: 'success',
          uuid: id
        }.to_json
      end

      it 'returns unauthorized status' do
        get "/check_in/v2/sessions/#{id}/appointments"

        expect(response).to have_http_status(:unauthorized)
      end

      it 'returns read.none permissions' do
        get "/check_in/v2/sessions/#{id}/appointments"

        expect(response.body).to eq(resp)
      end
    end

    context 'invalid params' do
      let(:session_params) do
        {
          params: {
            session: {
              uuid: id,
              dob: '1960-03-12',
              last_name: 'Johnson'
            }
          }
        }
      end

      before do
        VCR.use_cassette 'check_in/lorota/token/token_200' do
          post '/check_in/v2/sessions', **session_params
          expect(response).to have_http_status(:ok)
        end
      end

      it 'returns bad request when start date is invalid' do
        get "/check_in/v2/sessions/#{id}/appointments", params: { start: 'abc', end: '2023-12-12' }

        expect(response).to have_http_status(:bad_request)
      end

      it 'returns bad request when end date is invalid' do
        get "/check_in/v2/sessions/#{id}/appointments", params: { start: '2023-12-12', end: 'xyz' }

        expect(response).to have_http_status(:bad_request)
      end
    end

    context 'when session is not authorized' do
      let(:start_date) { '2023-11-10' }
      let(:end_date) { '2023-12-12' }
      let(:error_response) do
        {
          permissions: 'read.none',
          status: 'success',
          uuid: id
        }.to_json
      end

      it 'returns unauthorized response' do
        get "/check_in/v2/sessions/#{id}/appointments", params: { start: start_date, end: end_date }

        expect(response).to have_http_status(:unauthorized)
        expect(response.body).to eq(error_response)
      end
    end

    context 'with valid LoROTA session' do
      let(:session_params) do
        {
          params: {
            session: {
              uuid: id,
              dob: '1960-03-12',
              last_name: 'Johnson'
            }
          }
        }
      end
      let(:start_date) { '2023-11-10' }
      let(:end_date) { '2023-12-12' }

      before do
        VCR.use_cassette 'check_in/lorota/token/token_200' do
          post '/check_in/v2/sessions', **session_params
          expect(response).to have_http_status(:ok)
        end

        VCR.use_cassette('check_in/lorota/data/data_200', match_requests_on: [:host]) do
          VCR.use_cassette 'check_in/chip/set_echeckin_started/set_echeckin_started_200' do
            VCR.use_cassette 'check_in/chip/token/token_200' do
              get "/check_in/v2/patient_check_ins/#{id}"
              expect(response).to have_http_status(:ok)
            end
          end
        end
      end

      context 'when appointment service returns successfully' do
        let(:appts_response) do
          {
            data: [
              {
                id: '180766',
                type: 'appointments',
                attributes: {
                  kind: 'clinic',
                  status: 'booked',
                  serviceType: 'amputation',
                  locationId: '534',
                  clinic: '1081',
                  start: '2023-11-13T16:00:00Z',
                  end: '2023-11-13T16:30:00Z',
                  minutesDuration: 30,
                  telehealth: {
                    vvsKind: nil,
                    atlas: nil
                  },
                  extension: {
                    preCheckinAllowed: true,
                    eCheckinAllowed: true,
                    patientHasMobileGfe: nil
                  },
                  serviceCategory: [{
                    text: 'REGULAR'
                  }],
                  facilityName: 'Ralph H. Johnson Department of Veterans Affairs Medical Center',
                  facilityVistaSite: '534',
                  facilityTimezone: 'America/New_York',
                  facilityPhoneMain: '843-577-5011',
                  clinicServiceName: 'CHS NEUROSURGERY VARMA',
                  clinicPhysicalLocation: '1ST FL SPECIALTY MODULE 2',
                  clinicFriendlyName: 'CHS NEUROSURGERY VARMA'
                }
              },
              {
                id: '180770',
                type: 'appointments',
                attributes: {
                  kind: 'clinic',
                  status: 'booked',
                  serviceType: 'amputation',
                  locationId: '534',
                  clinic: '1081',
                  start: '2023-12-11T16:00:00Z',
                  end: '2023-12-11T16:30:00Z',
                  minutesDuration: 30,
                  telehealth: {
                    vvsKind: nil,
                    atlas: nil
                  },
                  extension: {
                    preCheckinAllowed: true,
                    eCheckinAllowed: true,
                    patientHasMobileGfe: nil
                  },
                  serviceCategory: [{
                    text: 'REGULAR'
                  }],
                  facilityName: 'Ralph H. Johnson Department of Veterans Affairs Medical Center',
                  facilityVistaSite: '534',
                  facilityTimezone: 'America/New_York',
                  facilityPhoneMain: '843-577-5011',
                  clinicServiceName: 'CHS NEUROSURGERY VARMA',
                  clinicPhysicalLocation: '1ST FL SPECIALTY MODULE 2',
                  clinicFriendlyName: 'CHS NEUROSURGERY VARMA'
                }
              }
            ]
          }.to_json
        end

        it 'returns appointments' do
          VCR.use_cassette 'check_in/clinics/get_clinics_200' do
            VCR.use_cassette 'check_in/facilities/get_facilities_200' do
              VCR.use_cassette 'check_in/appointments/get_appointments_200' do
                VCR.use_cassette 'map/security_token_service_200_response' do
                  get "/check_in/v2/sessions/#{id}/appointments", params: { start: start_date, end: end_date }
                end
              end
            end
          end

          expect(response).to have_http_status(:ok)
          expect(response.body).to eq(appts_response)
        end

        it 'does not increment clinic id observability metrics when flipper is disabled' do
          allow(Flipper).to receive(:enabled?)
            .with(:check_in_experience_appointments_clinic_observability_enabled)
            .and_return(false)
          allow(StatsD).to receive(:increment)
          VCR.use_cassette 'check_in/clinics/get_clinics_200' do
            VCR.use_cassette 'check_in/facilities/get_facilities_200' do
              VCR.use_cassette 'check_in/appointments/get_appointments_200' do
                VCR.use_cassette 'map/security_token_service_200_response' do
                  get "/check_in/v2/sessions/#{id}/appointments", params: { start: start_date, end: end_date }
                end
              end
            end
          end

          expect(StatsD).not_to have_received(:increment).with(
            CheckIn::Constants::STATSD_V2_APPOINTMENTS_CLINIC_OBSERVABILITY_TOTAL, anything
          )
        end

        context 'when clinic observability flipper is enabled' do
          before do
            allow(Flipper).to receive(:enabled?)
              .with(:check_in_experience_appointments_clinic_observability_enabled)
              .and_return(true)
          end

          it 'increments total, present, and missing-or-empty clinic key metrics' do
            allow(StatsD).to receive(:increment)
            VCR.use_cassette 'check_in/clinics/get_clinics_200' do
              VCR.use_cassette 'check_in/facilities/get_facilities_200' do
                VCR.use_cassette 'check_in/appointments/get_appointments_200' do
                  VCR.use_cassette 'map/security_token_service_200_response' do
                    get "/check_in/v2/sessions/#{id}/appointments", params: { start: start_date, end: end_date }
                  end
                end
              end
            end

            expect(StatsD).to have_received(:increment)
              .with(CheckIn::Constants::STATSD_V2_APPOINTMENTS_CLINIC_OBSERVABILITY_TOTAL, 2).once
            expect(StatsD).to have_received(:increment)
              .with(CheckIn::Constants::STATSD_V2_APPOINTMENTS_CLINIC_KEY_PRESENT, 2).once
            expect(StatsD).to have_received(:increment)
              .with(CheckIn::Constants::STATSD_V2_APPOINTMENTS_CLINIC_KEY_MISSING_OR_EMPTY, 0).once
            expect(StatsD).to have_received(:increment)
              .with(CheckIn::Constants::STATSD_V2_APPOINTMENTS_CLINIC_ENRICHMENT_TOTAL, 2).once
            expect(StatsD).to have_received(:increment)
              .with(CheckIn::Constants::STATSD_V2_APPOINTMENTS_CLINIC_ENRICHMENT_PRESENT, 2).once
            expect(StatsD).to have_received(:increment)
              .with(CheckIn::Constants::STATSD_V2_APPOINTMENTS_CLINIC_ENRICHMENT_MISSING, 0).once
          end
        end
      end

      context 'when appointment service returns successfully without location id for single appointment' do
        let(:appts_response) do
          {
            data: [
              {
                id: '180766',
                type: 'appointments',
                attributes: {
                  kind: 'clinic',
                  status: 'booked',
                  serviceType: 'amputation',
                  locationId: nil,
                  clinic: '1024',
                  start: '2023-11-13T16:00:00Z',
                  end: '2023-11-13T16:30:00Z',
                  minutesDuration: 30,
                  telehealth: {
                    vvsKind: nil,
                    atlas: nil
                  },
                  extension: {
                    preCheckinAllowed: true,
                    eCheckinAllowed: true,
                    patientHasMobileGfe: nil
                  },
                  serviceCategory: [{
                    text: 'REGULAR'
                  }],
                  facilityName: nil,
                  facilityVistaSite: nil,
                  facilityTimezone: nil,
                  facilityPhoneMain: nil,
                  clinicServiceName: nil,
                  clinicPhysicalLocation: nil,
                  clinicFriendlyName: nil
                }
              },
              {
                id: '180770',
                type: 'appointments',
                attributes: {
                  kind: 'clinic',
                  status: 'booked',
                  serviceType: 'amputation',
                  locationId: '534',
                  clinic: '1081',
                  start: '2023-12-11T16:00:00Z',
                  end: '2023-12-11T16:30:00Z',
                  minutesDuration: 30,
                  telehealth: {
                    vvsKind: nil,
                    atlas: nil
                  },
                  extension: {
                    preCheckinAllowed: true,
                    eCheckinAllowed: true,
                    patientHasMobileGfe: nil
                  },
                  serviceCategory: [{
                    text: 'REGULAR'
                  }],
                  facilityName: 'Ralph H. Johnson Department of Veterans Affairs Medical Center',
                  facilityVistaSite: '534',
                  facilityTimezone: 'America/New_York',
                  facilityPhoneMain: '843-577-5011',
                  clinicServiceName: 'CHS NEUROSURGERY VARMA',
                  clinicPhysicalLocation: '1ST FL SPECIALTY MODULE 2',
                  clinicFriendlyName: 'CHS NEUROSURGERY VARMA'
                }
              }
            ]
          }.to_json
        end

        it 'returns appointments' do
          VCR.use_cassette 'check_in/clinics/get_clinics_200' do
            VCR.use_cassette 'check_in/facilities/get_facilities_200' do
              VCR.use_cassette 'check_in/appointments/get_appointments_without_location_200' do
                VCR.use_cassette 'map/security_token_service_200_response' do
                  get "/check_in/v2/sessions/#{id}/appointments", params: { start: start_date, end: end_date }
                end
              end
            end
          end
          expect(response).to have_http_status(:ok)
          expect(response.body).to eq(appts_response)
        end
      end

      context 'when appointment service returns successfully without clinic' do
        let(:appts_response) do
          {
            data: [
              {
                id: '180766',
                type: 'appointments',
                attributes: {
                  kind: 'clinic',
                  status: 'booked',
                  serviceType: 'amputation',
                  locationId: '534',
                  clinic: nil,
                  start: '2023-11-13T16:00:00Z',
                  end: '2023-11-13T16:30:00Z',
                  minutesDuration: 30,
                  telehealth: {
                    vvsKind: nil,
                    atlas: nil
                  },
                  extension: {
                    preCheckinAllowed: true,
                    eCheckinAllowed: true,
                    patientHasMobileGfe: nil
                  },
                  serviceCategory: [{
                    text: 'REGULAR'
                  }],
                  facilityName: 'Ralph H. Johnson Department of Veterans Affairs Medical Center',
                  facilityVistaSite: '534',
                  facilityTimezone: 'America/New_York',
                  facilityPhoneMain: '843-577-5011',
                  clinicServiceName: nil,
                  clinicPhysicalLocation: nil,
                  clinicFriendlyName: nil
                }
              },
              {
                id: '180770',
                type: 'appointments',
                attributes: {
                  kind: 'clinic',
                  status: 'booked',
                  serviceType: 'amputation',
                  locationId: '534',
                  clinic: nil,
                  start: '2023-12-11T16:00:00Z',
                  end: '2023-12-11T16:30:00Z',
                  minutesDuration: 30,
                  telehealth: {
                    vvsKind: nil,
                    atlas: nil
                  },
                  extension: {
                    preCheckinAllowed: true,
                    eCheckinAllowed: true,
                    patientHasMobileGfe: nil
                  },
                  serviceCategory: [{
                    text: 'REGULAR'
                  }],
                  facilityName: 'Ralph H. Johnson Department of Veterans Affairs Medical Center',
                  facilityVistaSite: '534',
                  facilityTimezone: 'America/New_York',
                  facilityPhoneMain: '843-577-5011',
                  clinicServiceName: nil,
                  clinicPhysicalLocation: nil,
                  clinicFriendlyName: nil
                }
              }
            ]
          }.to_json
        end

        it 'returns appointments' do
          VCR.use_cassette 'check_in/facilities/get_facilities_200' do
            VCR.use_cassette 'check_in/appointments/get_appointments_without_clinic_200' do
              VCR.use_cassette 'map/security_token_service_200_response' do
                get "/check_in/v2/sessions/#{id}/appointments", params: { start: start_date, end: end_date }
              end
            end
          end

          expect(response).to have_http_status(:ok)
          expect(response.body).to eq(appts_response)
        end

        context 'when clinic observability flipper is enabled' do
          before do
            allow(Flipper).to receive(:enabled?)
              .with(:check_in_experience_appointments_clinic_observability_enabled)
              .and_return(true)
          end

          it 'increments total and missing-or-empty clinic key metrics when clinic is absent' do
            allow(StatsD).to receive(:increment)
            VCR.use_cassette 'check_in/facilities/get_facilities_200' do
              VCR.use_cassette 'check_in/appointments/get_appointments_without_clinic_200' do
                VCR.use_cassette 'map/security_token_service_200_response' do
                  get "/check_in/v2/sessions/#{id}/appointments", params: { start: start_date, end: end_date }
                end
              end
            end

            expect(StatsD).to have_received(:increment)
              .with(CheckIn::Constants::STATSD_V2_APPOINTMENTS_CLINIC_OBSERVABILITY_TOTAL, 2).once
            expect(StatsD).to have_received(:increment)
              .with(CheckIn::Constants::STATSD_V2_APPOINTMENTS_CLINIC_KEY_PRESENT, 0).once
            expect(StatsD).to have_received(:increment)
              .with(CheckIn::Constants::STATSD_V2_APPOINTMENTS_CLINIC_KEY_MISSING_OR_EMPTY, 2).once
          end
        end
      end

      context 'when appointment service returns 500' do
        let(:error_response) do
          {
            errors: [
              {
                title: 'Operation failed',
                detail: 'Operation failed',
                code: 'VA900',
                status: '400'
              }
            ]
          }.to_json
        end

        it 'returns error' do
          VCR.use_cassette 'check_in/appointments/get_appointments_500' do
            VCR.use_cassette 'map/security_token_service_200_response' do
              get "/check_in/v2/sessions/#{id}/appointments", params: { start: start_date, end: end_date }
            end
          end

          expect(response).to have_http_status(:bad_request)
          expect(response.body).to eq(error_response)
        end
      end

      context 'when facility service returns 500' do
        # Enrichment is best-effort: a facility failure must not fail the whole appointments
        # response. The appointment is still returned with the facility fields left blank.
        it 'returns appointments with facility fields blank and records the enrichment failure' do
          allow(StatsD).to receive(:increment)

          VCR.use_cassette 'check_in/clinics/get_clinics_200' do
            VCR.use_cassette 'check_in/facilities/get_facilities_500' do
              VCR.use_cassette 'check_in/appointments/get_appointments_200' do
                VCR.use_cassette 'map/security_token_service_200_response' do
                  get "/check_in/v2/sessions/#{id}/appointments", params: { start: start_date, end: end_date }
                end
              end
            end
          end

          expect(response).to have_http_status(:ok)
          expect(response.parsed_body['data'].map { |appt| appt['id'] }).to eq(%w[180766 180770])
          attributes = response.parsed_body['data'].map { |appt| appt['attributes'] }
          expect(attributes.map { |attr| attr['facilityName'] }).to all(be_nil)
          expect(StatsD).to have_received(:increment)
            .with(CheckIn::Constants::STATSD_FACILITY_ENRICHMENT_FAILED).at_least(:once)
        end

        context 'when clinic observability flipper is enabled' do
          before do
            allow(Flipper).to receive(:enabled?)
              .with(:check_in_experience_appointments_clinic_observability_enabled)
              .and_return(true)
          end

          it 'still records clinic key observability when facility enrichment fails' do
            allow(StatsD).to receive(:increment)

            VCR.use_cassette 'check_in/clinics/get_clinics_200' do
              VCR.use_cassette 'check_in/facilities/get_facilities_500' do
                VCR.use_cassette 'check_in/appointments/get_appointments_200' do
                  VCR.use_cassette 'map/security_token_service_200_response' do
                    get "/check_in/v2/sessions/#{id}/appointments", params: { start: start_date, end: end_date }
                  end
                end
              end
            end

            expect(response).to have_http_status(:ok)
            expect(StatsD).to have_received(:increment)
              .with(CheckIn::Constants::STATSD_V2_APPOINTMENTS_CLINIC_OBSERVABILITY_TOTAL, 2).once
            expect(StatsD).to have_received(:increment)
              .with(CheckIn::Constants::STATSD_V2_APPOINTMENTS_CLINIC_KEY_PRESENT, 2).once
            expect(StatsD).to have_received(:increment)
              .with(CheckIn::Constants::STATSD_V2_APPOINTMENTS_CLINIC_KEY_MISSING_OR_EMPTY, 0).once
          end
        end
      end

      context 'when facility service succeeds 200 but clinic service returns 500' do
        it 'returns appointments with clinic fields blank and records the enrichment failure' do
          allow(StatsD).to receive(:increment)

          VCR.use_cassette 'check_in/clinics/get_clinics_500' do
            VCR.use_cassette 'check_in/facilities/get_facilities_200' do
              VCR.use_cassette 'check_in/appointments/get_appointments_200' do
                VCR.use_cassette 'map/security_token_service_200_response' do
                  get "/check_in/v2/sessions/#{id}/appointments", params: { start: start_date, end: end_date }
                end
              end
            end
          end

          expect(response).to have_http_status(:ok)
          attributes = response.parsed_body['data'].map { |appt| appt['attributes'] }
          expect(attributes.map { |attr| attr['facilityName'] }).to all(be_present)
          expect(attributes.map { |attr| attr['clinicServiceName'] }).to all(be_nil)
          expect(StatsD).to have_received(:increment)
            .with(CheckIn::Constants::STATSD_CLINIC_ENRICHMENT_FAILED).at_least(:once)
        end
      end

      context 'when VA Mobile facilities v3 is enabled' do
        # Single-facility MFS v3 contract: see mfs-v3.json in this directory (getFacilityById).
        before do
          allow(Flipper).to receive(:enabled?)
            .with(:check_in_experience_va_mobile_facilities_v3_enabled)
            .and_return(true)
        end

        context 'when appointment service returns successfully' do
          let(:appts_response) do
            {
              data: [
                {
                  id: '180766',
                  type: 'appointments',
                  attributes: {
                    kind: 'clinic',
                    status: 'booked',
                    serviceType: 'amputation',
                    locationId: '534',
                    clinic: '1081',
                    start: '2023-11-13T16:00:00Z',
                    end: '2023-11-13T16:30:00Z',
                    minutesDuration: 30,
                    telehealth: {
                      vvsKind: nil,
                      atlas: nil
                    },
                    extension: {
                      preCheckinAllowed: true,
                      eCheckinAllowed: true,
                      patientHasMobileGfe: nil
                    },
                    serviceCategory: [{
                      text: 'REGULAR'
                    }],
                    facilityName: 'Ralph H. Johnson Department of Veterans Affairs Medical Center',
                    facilityVistaSite: '534',
                    facilityTimezone: 'America/New_York',
                    facilityPhoneMain: '843-577-5011',
                    clinicServiceName: nil,
                    clinicPhysicalLocation: nil,
                    clinicFriendlyName: nil
                  }
                },
                {
                  id: '180770',
                  type: 'appointments',
                  attributes: {
                    kind: 'clinic',
                    status: 'booked',
                    serviceType: 'amputation',
                    locationId: '534',
                    clinic: '1081',
                    start: '2023-12-11T16:00:00Z',
                    end: '2023-12-11T16:30:00Z',
                    minutesDuration: 30,
                    telehealth: {
                      vvsKind: nil,
                      atlas: nil
                    },
                    extension: {
                      preCheckinAllowed: true,
                      eCheckinAllowed: true,
                      patientHasMobileGfe: nil
                    },
                    serviceCategory: [{
                      text: 'REGULAR'
                    }],
                    facilityName: 'Ralph H. Johnson Department of Veterans Affairs Medical Center',
                    facilityVistaSite: '534',
                    facilityTimezone: 'America/New_York',
                    facilityPhoneMain: '843-577-5011',
                    clinicServiceName: nil,
                    clinicPhysicalLocation: nil,
                    clinicFriendlyName: nil
                  }
                }
              ]
            }.to_json
          end

          it 'returns appointments using MFS v3 without clinic enrichment' do
            allow(StatsD).to receive(:increment)

            VCR.use_cassette 'check_in/facilities/get_facilities_v3_200' do
              VCR.use_cassette 'check_in/appointments/get_appointments_200' do
                VCR.use_cassette 'map/security_token_service_200_response' do
                  get "/check_in/v2/sessions/#{id}/appointments", params: { start: start_date, end: end_date }
                end
              end
            end

            expect(response).to have_http_status(:ok)
            expect(response.body).to eq(appts_response)
            expect(StatsD).to have_received(:increment).with(
              CheckIn::Constants::STATSD_VDS_SITE_INFO_CLINICS_SKIPPED_FLAG_OFF
            ).once
          end

          context 'when clinic observability flipper is enabled' do
            before do
              allow(Flipper).to receive(:enabled?)
                .with(:check_in_experience_appointments_clinic_observability_enabled)
                .and_return(true)
            end

            it 'records clinic keys present but enrichment missing during v3-only rollout' do
              allow(StatsD).to receive(:increment)

              VCR.use_cassette 'check_in/facilities/get_facilities_v3_200' do
                VCR.use_cassette 'check_in/appointments/get_appointments_200' do
                  VCR.use_cassette 'map/security_token_service_200_response' do
                    get "/check_in/v2/sessions/#{id}/appointments", params: { start: start_date, end: end_date }
                  end
                end
              end

              expect(StatsD).to have_received(:increment)
                .with(CheckIn::Constants::STATSD_V2_APPOINTMENTS_CLINIC_KEY_PRESENT, 2).once
              expect(StatsD).to have_received(:increment)
                .with(CheckIn::Constants::STATSD_V2_APPOINTMENTS_CLINIC_ENRICHMENT_PRESENT, 0).once
              expect(StatsD).to have_received(:increment)
                .with(CheckIn::Constants::STATSD_V2_APPOINTMENTS_CLINIC_ENRICHMENT_MISSING, 2).once
            end
          end
        end

        context 'when facilities v3 and VDS site info clinics are enabled' do
          before do
            allow(Flipper).to receive(:enabled?)
              .with(:check_in_experience_vds_site_info_clinics_enabled)
              .and_return(true)
          end

          context 'when appointment service returns successfully' do
            let(:appts_response) do
              {
                data: [
                  {
                    id: '180766',
                    type: 'appointments',
                    attributes: {
                      kind: 'clinic',
                      status: 'booked',
                      serviceType: 'amputation',
                      locationId: '534',
                      clinic: '1081',
                      start: '2023-11-13T16:00:00Z',
                      end: '2023-11-13T16:30:00Z',
                      minutesDuration: 30,
                      telehealth: {
                        vvsKind: nil,
                        atlas: nil
                      },
                      extension: {
                        preCheckinAllowed: true,
                        eCheckinAllowed: true,
                        patientHasMobileGfe: nil
                      },
                      serviceCategory: [{
                        text: 'REGULAR'
                      }],
                      facilityName: 'Ralph H. Johnson Department of Veterans Affairs Medical Center',
                      facilityVistaSite: '534',
                      facilityTimezone: 'America/New_York',
                      facilityPhoneMain: '843-577-5011',
                      clinicServiceName: 'CHS NEUROSURGERY VARMA',
                      clinicPhysicalLocation: '1ST FL SPECIALTY MODULE 2',
                      clinicFriendlyName: 'CHS NEUROSURGERY VARMA'
                    }
                  },
                  {
                    id: '180770',
                    type: 'appointments',
                    attributes: {
                      kind: 'clinic',
                      status: 'booked',
                      serviceType: 'amputation',
                      locationId: '534',
                      clinic: '1081',
                      start: '2023-12-11T16:00:00Z',
                      end: '2023-12-11T16:30:00Z',
                      minutesDuration: 30,
                      telehealth: {
                        vvsKind: nil,
                        atlas: nil
                      },
                      extension: {
                        preCheckinAllowed: true,
                        eCheckinAllowed: true,
                        patientHasMobileGfe: nil
                      },
                      serviceCategory: [{
                        text: 'REGULAR'
                      }],
                      facilityName: 'Ralph H. Johnson Department of Veterans Affairs Medical Center',
                      facilityVistaSite: '534',
                      facilityTimezone: 'America/New_York',
                      facilityPhoneMain: '843-577-5011',
                      clinicServiceName: 'CHS NEUROSURGERY VARMA',
                      clinicPhysicalLocation: '1ST FL SPECIALTY MODULE 2',
                      clinicFriendlyName: 'CHS NEUROSURGERY VARMA'
                    }
                  }
                ]
              }.to_json
            end

            it 'returns appointments using MFS v3 with VDS-Site-Info clinic enrichment' do
              VCR.use_cassette 'check_in/vds_site_info/get_site_clinics_200' do
                VCR.use_cassette 'check_in/facilities/get_facilities_v3_200' do
                  VCR.use_cassette 'check_in/appointments/get_appointments_200' do
                    VCR.use_cassette 'map/security_token_service_200_response' do
                      get "/check_in/v2/sessions/#{id}/appointments", params: { start: start_date, end: end_date }
                    end
                  end
                end
              end

              expect(response).to have_http_status(:ok)
              expect(response.body).to eq(appts_response)
            end
          end

          context 'when facility service succeeds 200 but VDS clinic service returns 500' do
            # A non-VistA (Oracle Health) site_id sent to the VDS site-info endpoint returns an
            # error; the appointment is still returned with the facility info but no clinic info.
            it 'returns appointments with clinic fields blank and records the enrichment failure' do
              allow(StatsD).to receive(:increment)

              VCR.use_cassette 'check_in/vds_site_info/get_site_clinics_500' do
                VCR.use_cassette 'check_in/facilities/get_facilities_v3_200' do
                  VCR.use_cassette 'check_in/appointments/get_appointments_200' do
                    VCR.use_cassette 'map/security_token_service_200_response' do
                      get "/check_in/v2/sessions/#{id}/appointments", params: { start: start_date, end: end_date }
                    end
                  end
                end
              end

              expect(response).to have_http_status(:ok)
              attributes = response.parsed_body['data'].map { |appt| appt['attributes'] }
              expect(attributes.map { |attr| attr['facilityName'] }).to all(be_present)
              expect(attributes.map { |attr| attr['clinicServiceName'] }).to all(be_nil)
              expect(StatsD).to have_received(:increment)
                .with(CheckIn::Constants::STATSD_CLINIC_ENRICHMENT_FAILED).at_least(:once)
            end

            context 'when clinic observability flipper is enabled' do
              before do
                allow(Flipper).to receive(:enabled?)
                  .with(:check_in_experience_appointments_clinic_observability_enabled)
                  .and_return(true)
              end

              it 'still records clinic key observability when VDS clinic enrichment fails' do
                allow(StatsD).to receive(:increment)

                VCR.use_cassette 'check_in/vds_site_info/get_site_clinics_500' do
                  VCR.use_cassette 'check_in/facilities/get_facilities_v3_200' do
                    VCR.use_cassette 'check_in/appointments/get_appointments_200' do
                      VCR.use_cassette 'map/security_token_service_200_response' do
                        get "/check_in/v2/sessions/#{id}/appointments",
                            params: { start: start_date, end: end_date }
                      end
                    end
                  end
                end

                expect(response).to have_http_status(:ok)
                expect(StatsD).to have_received(:increment)
                  .with(CheckIn::Constants::STATSD_V2_APPOINTMENTS_CLINIC_OBSERVABILITY_TOTAL, 2).once
                expect(StatsD).to have_received(:increment)
                  .with(CheckIn::Constants::STATSD_V2_APPOINTMENTS_CLINIC_KEY_PRESENT, 2).once
                expect(StatsD).to have_received(:increment)
                  .with(CheckIn::Constants::STATSD_V2_APPOINTMENTS_CLINIC_KEY_MISSING_OR_EMPTY, 0).once
              end
            end
          end
        end

        context 'when appointment service returns successfully without location id for single appointment' do
          let(:appts_response) do
            {
              data: [
                {
                  id: '180766',
                  type: 'appointments',
                  attributes: {
                    kind: 'clinic',
                    status: 'booked',
                    serviceType: 'amputation',
                    locationId: nil,
                    clinic: '1024',
                    start: '2023-11-13T16:00:00Z',
                    end: '2023-11-13T16:30:00Z',
                    minutesDuration: 30,
                    telehealth: {
                      vvsKind: nil,
                      atlas: nil
                    },
                    extension: {
                      preCheckinAllowed: true,
                      eCheckinAllowed: true,
                      patientHasMobileGfe: nil
                    },
                    serviceCategory: [{
                      text: 'REGULAR'
                    }],
                    facilityName: nil,
                    facilityVistaSite: nil,
                    facilityTimezone: nil,
                    facilityPhoneMain: nil,
                    clinicServiceName: nil,
                    clinicPhysicalLocation: nil,
                    clinicFriendlyName: nil
                  }
                },
                {
                  id: '180770',
                  type: 'appointments',
                  attributes: {
                    kind: 'clinic',
                    status: 'booked',
                    serviceType: 'amputation',
                    locationId: '534',
                    clinic: '1081',
                    start: '2023-12-11T16:00:00Z',
                    end: '2023-12-11T16:30:00Z',
                    minutesDuration: 30,
                    telehealth: {
                      vvsKind: nil,
                      atlas: nil
                    },
                    extension: {
                      preCheckinAllowed: true,
                      eCheckinAllowed: true,
                      patientHasMobileGfe: nil
                    },
                    serviceCategory: [{
                      text: 'REGULAR'
                    }],
                    facilityName: 'Ralph H. Johnson Department of Veterans Affairs Medical Center',
                    facilityVistaSite: '534',
                    facilityTimezone: 'America/New_York',
                    facilityPhoneMain: '843-577-5011',
                    clinicServiceName: nil,
                    clinicPhysicalLocation: nil,
                    clinicFriendlyName: nil
                  }
                }
              ]
            }.to_json
          end

          it 'returns appointments' do
            VCR.use_cassette 'check_in/facilities/get_facilities_v3_200' do
              VCR.use_cassette 'check_in/appointments/get_appointments_without_location_200' do
                VCR.use_cassette 'map/security_token_service_200_response' do
                  get "/check_in/v2/sessions/#{id}/appointments", params: { start: start_date, end: end_date }
                end
              end
            end

            expect(response).to have_http_status(:ok)
            expect(response.body).to eq(appts_response)
          end
        end

        context 'when appointment service returns successfully without clinic' do
          let(:appts_response) do
            {
              data: [
                {
                  id: '180766',
                  type: 'appointments',
                  attributes: {
                    kind: 'clinic',
                    status: 'booked',
                    serviceType: 'amputation',
                    locationId: '534',
                    clinic: nil,
                    start: '2023-11-13T16:00:00Z',
                    end: '2023-11-13T16:30:00Z',
                    minutesDuration: 30,
                    telehealth: {
                      vvsKind: nil,
                      atlas: nil
                    },
                    extension: {
                      preCheckinAllowed: true,
                      eCheckinAllowed: true,
                      patientHasMobileGfe: nil
                    },
                    serviceCategory: [{
                      text: 'REGULAR'
                    }],
                    facilityName: 'Ralph H. Johnson Department of Veterans Affairs Medical Center',
                    facilityVistaSite: '534',
                    facilityTimezone: 'America/New_York',
                    facilityPhoneMain: '843-577-5011',
                    clinicServiceName: nil,
                    clinicPhysicalLocation: nil,
                    clinicFriendlyName: nil
                  }
                },
                {
                  id: '180770',
                  type: 'appointments',
                  attributes: {
                    kind: 'clinic',
                    status: 'booked',
                    serviceType: 'amputation',
                    locationId: '534',
                    clinic: nil,
                    start: '2023-12-11T16:00:00Z',
                    end: '2023-12-11T16:30:00Z',
                    minutesDuration: 30,
                    telehealth: {
                      vvsKind: nil,
                      atlas: nil
                    },
                    extension: {
                      preCheckinAllowed: true,
                      eCheckinAllowed: true,
                      patientHasMobileGfe: nil
                    },
                    serviceCategory: [{
                      text: 'REGULAR'
                    }],
                    facilityName: 'Ralph H. Johnson Department of Veterans Affairs Medical Center',
                    facilityVistaSite: '534',
                    facilityTimezone: 'America/New_York',
                    facilityPhoneMain: '843-577-5011',
                    clinicServiceName: nil,
                    clinicPhysicalLocation: nil,
                    clinicFriendlyName: nil
                  }
                }
              ]
            }.to_json
          end

          it 'returns appointments' do
            VCR.use_cassette 'check_in/facilities/get_facilities_v3_200' do
              VCR.use_cassette 'check_in/appointments/get_appointments_without_clinic_200' do
                VCR.use_cassette 'map/security_token_service_200_response' do
                  get "/check_in/v2/sessions/#{id}/appointments", params: { start: start_date, end: end_date }
                end
              end
            end

            expect(response).to have_http_status(:ok)
            expect(response.body).to eq(appts_response)
          end
        end

        context 'when appointment service returns 500' do
          let(:error_response) do
            {
              errors: [
                {
                  title: 'Operation failed',
                  detail: 'Operation failed',
                  code: 'VA900',
                  status: '400'
                }
              ]
            }.to_json
          end

          it 'returns error' do
            VCR.use_cassette 'check_in/appointments/get_appointments_500' do
              VCR.use_cassette 'map/security_token_service_200_response' do
                get "/check_in/v2/sessions/#{id}/appointments", params: { start: start_date, end: end_date }
              end
            end

            expect(response).to have_http_status(:bad_request)
            expect(response.body).to eq(error_response)
          end
        end

        context 'when facility service returns 500' do
          it 'returns appointments with facility fields blank and records the enrichment failure' do
            allow(StatsD).to receive(:increment)

            VCR.use_cassette 'check_in/facilities/get_facilities_v3_500' do
              VCR.use_cassette 'check_in/appointments/get_appointments_200' do
                VCR.use_cassette 'map/security_token_service_200_response' do
                  get "/check_in/v2/sessions/#{id}/appointments", params: { start: start_date, end: end_date }
                end
              end
            end

            expect(response).to have_http_status(:ok)
            attributes = response.parsed_body['data'].map { |appt| appt['attributes'] }
            expect(attributes.map { |attr| attr['facilityName'] }).to all(be_nil)
            expect(StatsD).to have_received(:increment)
              .with(CheckIn::Constants::STATSD_FACILITY_ENRICHMENT_FAILED).at_least(:once)
          end
        end
      end
    end
  end
end
