# frozen_string_literal: true

require 'rails_helper'

describe CheckIn::VAOS::FacilityService do
  subject { described_class.new }

  let(:facility_id) { '500' }
  let(:clinic_id) { '6' }
  let(:memory_store) { ActiveSupport::Cache.lookup_store(:memory_store) }

  before do
    allow(Rails).to receive(:cache).and_return(memory_store)
    Rails.cache.clear
    allow(Flipper).to receive(:enabled?)
      .with(:check_in_experience_va_mobile_facilities_v3_enabled)
      .and_return(false)
    allow(Flipper).to receive(:enabled?)
      .with(:check_in_experience_vds_site_info_clinics_enabled)
      .and_return(false)
  end

  describe '.build' do
    it 'returns an instance of Service' do
      expect(subject).to be_an_instance_of(described_class)
    end
  end

  describe '#perform' do
    let(:facility_response) do
      {
        id: '500',
        facilitiesApiId: 'vha_500',
        vistaSite: '500',
        vastParent: '500',
        type: 'va_health_facility',
        name: 'Johnson & Johnson',
        classification: 'MC',
        timezone: {
          timeZoneId: 'America/New_York'
        },
        lat: 32.78447,
        long: -79.95415,
        phone: {
          main: '123-456-7890',
          fax: '456-892-7890',
          pharmacy: '632-456-6734',
          afterHours: '642-632-8932'
        }
      }
    end
    let(:faraday_response) { double('Faraday::Response') }
    let(:faraday_env) { double('Faraday::Env', status: 200, body: facility_response.to_json) }

    context 'when no facilities data in cache, vaos returns successful response' do
      before do
        allow_any_instance_of(Faraday::Connection).to receive(:get)
          .with("/facilities/v2/facilities/#{facility_id}",
                {})
          .and_return(faraday_response)
        allow(faraday_response).to receive(:env).and_return(faraday_env)
      end

      it 'returns facility' do
        response = subject.get_facility(facility_id:)
        expect(response).to eq(facility_response.with_indifferent_access)
      end
    end

    context 'when VA Mobile facilities v3 flipper is enabled and vaos returns successful response' do
      before do
        allow(Flipper).to receive(:enabled?).with(:check_in_experience_va_mobile_facilities_v3_enabled).and_return(true)
        allow_any_instance_of(Faraday::Connection).to receive(:get)
          .with("/facilities/v3/facilities/#{facility_id}/",
                {})
          .and_return(faraday_response)
        allow(faraday_response).to receive(:env).and_return(faraday_env)
      end

      it 'returns facility from MFS v3 path' do
        response = subject.get_facility(facility_id:)
        expect(response).to eq(facility_response.with_indifferent_access)
      end
    end

    context 'when no clinic data in cache, vaos clinic api returns successful response' do
      let(:clinic_response) do
        {
          data: {
            vistaSite: 534,
            clinicId: clinic_id,
            serviceName: 'CHS NEUROSURGERY VARMA',
            friendlyName: 'CHS NEUROSURGERY VARMA',
            medicalService: 'SURGERY',
            physicalLocation: '1ST FL SPECIALTY MODULE 2',
            phoneNumber: '843-577-5011',
            stationId: '534',
            institutionId: '534',
            stationName: 'Ralph H. Johnson Department of Veterans Affairs Medical Center',
            primaryStopCode: 406,
            primaryStopCodeName: 'NEUROSURGERY',
            secondaryStopCodeName: '*Missing*',
            appointmentLength: 30,
            variableAppointmentLength: true,
            patientDirectScheduling: false,
            patientDisplay: true,
            institutionName: 'CHARLESTON VAMC',
            institutionIEN: '534',
            institutionSID: '97177',
            timezone: {
              timeZoneId: 'America/New_York'
            },
            futureBookingMaximumDays: 390
          }
        }
      end
      let(:faraday_response) { double('Faraday::Response') }
      let(:faraday_env) { double('Faraday::Env', status: 200, body: clinic_response.to_json) }

      before do
        allow_any_instance_of(Faraday::Connection).to receive(:get)
          .with("/facilities/v2/facilities/#{facility_id}/clinics/#{clinic_id}",
                {})
          .and_return(faraday_response)
        allow(faraday_response).to receive(:env).and_return(faraday_env)
      end

      it 'returns clinic data' do
        response = subject.get_clinic(facility_id:, clinic_id:)
        expect(response).to eq(clinic_response.with_indifferent_access)
      end

      context 'when facilities v3 and VDS site info clinics flippers are enabled' do
        let(:facility_id) { '534' }
        let(:clinic_id) { '1081' }
        let(:facility) { { vistaSite: facility_id }.with_indifferent_access }
        let(:vds_clinics) do
          [
            {
              clinicIen: clinic_id,
              name: 'CHS NEUROSURGERY VARMA',
              friendlyName: 'CHS NEUROSURGERY VARMA',
              physicalLocation: '1ST FL SPECIALTY MODULE 2'
            }
          ]
        end
        let(:mapped_clinic_response) do
          {
            data: {
              clinicId: clinic_id,
              serviceName: 'CHS NEUROSURGERY VARMA',
              friendlyName: 'CHS NEUROSURGERY VARMA',
              physicalLocation: '1ST FL SPECIALTY MODULE 2'
            }
          }
        end
        let(:faraday_response) { double('Faraday::Response') }
        let(:faraday_env) { double('Faraday::Env', status: 200, body: vds_clinics.to_json) }

        before do
          allow(Flipper).to receive(:enabled?)
            .with(:check_in_experience_va_mobile_facilities_v3_enabled)
            .and_return(true)
          allow(Flipper).to receive(:enabled?)
            .with(:check_in_experience_vds_site_info_clinics_enabled)
            .and_return(true)
          allow_any_instance_of(Faraday::Connection).to receive(:get)
            .with("/vds/info/v1/sites/#{facility_id}/clinics", {})
            .and_return(faraday_response)
          allow(faraday_response).to receive(:env).and_return(faraday_env)
        end

        it 'returns clinic data mapped from VDS-Site-Info list' do
          response = subject.get_clinic(facility_id:, clinic_id:, facility:)
          expect(response).to eq(mapped_clinic_response.with_indifferent_access)
        end

        it 'logs and metrics when clinic IEN is not in the VDS site list' do
          allow(StatsD).to receive(:increment)
          expect(Rails.logger).to receive(:info).with('HCE-Check-In')

          expect(subject.get_clinic(facility_id:, clinic_id: '9999', facility:)).to be_nil

          expect(StatsD).to have_received(:increment).with(
            CheckIn::Constants::STATSD_VDS_SITE_INFO_CLINICS_LOOKUP_MISS,
            tags: ['reason:clinic_ien_not_found']
          )
        end

        it 'logs and metrics when the VDS site clinic list is empty' do
          allow(StatsD).to receive(:increment)
          expect(Rails.logger).to receive(:info).with('HCE-Check-In')
          empty_env = double('Faraday::Env', status: 200, body: [].to_json)
          empty_response = double('Faraday::Response')
          allow(empty_response).to receive(:env).and_return(empty_env)
          allow_any_instance_of(Faraday::Connection).to receive(:get)
            .with("/vds/info/v1/sites/#{facility_id}/clinics", {})
            .and_return(empty_response)

          expect(subject.get_clinic(facility_id:, clinic_id:, facility:)).to be_nil

          expect(StatsD).to have_received(:increment).with(
            CheckIn::Constants::STATSD_VDS_SITE_INFO_CLINICS_LOOKUP_MISS,
            tags: ['reason:empty_site_list']
          )
        end

        it 'skips VDS lookup when facility enrichment did not provide vistaSite' do
          allow(StatsD).to receive(:increment)
          expect(Rails.logger).to receive(:info).with('HCE-Check-In')
          expect_any_instance_of(Faraday::Connection).not_to receive(:get)

          expect(subject.get_clinic(facility_id:, clinic_id:)).to be_nil

          expect(StatsD).to have_received(:increment).with(
            CheckIn::Constants::STATSD_VDS_SITE_INFO_CLINICS_VISTA_SITE_MISSING
          )
        end

        context 'when location_id is an institution id and facility has vistaSite' do
          let(:facility_id) { '983GC' }
          let(:vista_site_id) { '983' }
          let(:facility) { { vistaSite: vista_site_id }.with_indifferent_access }
          let(:vds_clinics) do
            [
              {
                clinicIen: clinic_id,
                name: 'FTC AMPUTATION',
                patientFriendlyName: 'Friendly Name FTC Amputation'
              }
            ]
          end
          let(:mapped_clinic_response) do
            {
              data: {
                clinicId: clinic_id,
                serviceName: 'FTC AMPUTATION',
                friendlyName: 'Friendly Name FTC Amputation',
                physicalLocation: nil
              }
            }
          end
          let(:faraday_response) { double('Faraday::Response') }
          let(:faraday_env) { double('Faraday::Env', status: 200, body: vds_clinics.to_json) }

          before do
            allow_any_instance_of(Faraday::Connection).to receive(:get)
              .with("/vds/info/v1/sites/#{vista_site_id}/clinics", {})
              .and_return(faraday_response)
            allow(faraday_response).to receive(:env).and_return(faraday_env)
          end

          it 'looks up clinics by vistaSite and maps patientFriendlyName' do
            response = subject.get_clinic(facility_id:, clinic_id:, facility:)
            expect(response).to eq(mapped_clinic_response.with_indifferent_access)
          end
        end
      end

      context 'when VDS site info clinics is enabled without facilities v3' do
        before do
          allow(Flipper).to receive(:enabled?)
            .with(:check_in_experience_vds_site_info_clinics_enabled)
            .and_return(true)
        end

        it 'uses MFS v2 clinic-by-id instead of VDS' do
          response = subject.get_clinic(facility_id:, clinic_id:)
          expect(response).to eq(clinic_response.with_indifferent_access)
        end

        it 'uses location_id for MFS v2 even when facility has vistaSite' do
          facility = { vistaSite: '983' }.with_indifferent_access
          expect_any_instance_of(Faraday::Connection).to receive(:get)
            .with("/facilities/v2/facilities/983GC/clinics/#{clinic_id}", {})
            .and_return(faraday_response)
          allow(faraday_response).to receive(:env).and_return(faraday_env)

          response = subject.get_clinic(facility_id: '983GC', clinic_id:, facility:)
          expect(response).to eq(clinic_response.with_indifferent_access)
        end
      end

      context 'when facilities v3 is enabled without VDS site info clinics' do
        before do
          allow(Flipper).to receive(:enabled?)
            .with(:check_in_experience_va_mobile_facilities_v3_enabled)
            .and_return(true)
        end

        it 'does not call VAOS for clinic data and returns nil' do
          expect_any_instance_of(Faraday::Connection).not_to receive(:get)
          expect(subject.get_clinic(facility_id:, clinic_id:)).to be_nil
        end

        it 'increments skipped_flag_off when track_vds_clinics_skipped_flag_off! is called' do
          allow(StatsD).to receive(:increment)
          expect(Rails.logger).to receive(:info).with('HCE-Check-In')

          subject.track_vds_clinics_skipped_flag_off!

          expect(StatsD).to have_received(:increment).with(
            CheckIn::Constants::STATSD_VDS_SITE_INFO_CLINICS_SKIPPED_FLAG_OFF
          ).once
        end
      end
    end

    context 'when facilities api return server error' do
      let(:resp) { Faraday::Response.new(body: { error: 'Internal server error' }, status: 500) }
      let(:exception) { Common::Exceptions::BackendServiceException.new(nil, {}, resp.status, resp.body) }

      before do
        allow_any_instance_of(Faraday::Connection).to receive(:get).and_raise(exception)
      end

      it 're-raises so the caller decides how to handle it' do
        expect do
          subject.get_facility(facility_id:)
        end.to(raise_error do |error|
          expect(error).to be_a(Common::Exceptions::BackendServiceException)
        end)
      end
    end

    context 'when clinics api return server error' do
      let(:resp) { Faraday::Response.new(body: { error: 'Internal server error' }, status: 500) }
      let(:exception) { Common::Exceptions::BackendServiceException.new(nil, {}, resp.status, resp.body) }

      before do
        allow_any_instance_of(Faraday::Connection).to receive(:get).and_raise(exception)
      end

      it 'throws exception' do
        expect do
          subject.get_clinic(facility_id:, clinic_id:)
        end.to(raise_error do |error|
          expect(error).to be_a(Common::Exceptions::BackendServiceException)
        end)
      end
    end
  end

  describe 'facilities api data from cache' do
    let(:facility_response) do
      {
        id: '500',
        facilitiesApiId: 'vha_500',
        vistaSite: '500',
        vastParent: '500',
        type: 'va_health_facility',
        name: 'Johnson & Johnson',
        classification: 'MC',
        timezone: {
          timeZoneId: 'America/New_York'
        },
        lat: 32.78447,
        long: -79.95415,
        phone: {
          main: '123-456-7890',
          fax: '456-892-7890',
          pharmacy: '632-456-6734',
          afterHours: '642-632-8932'
        }
      }
    end

    context 'when facility data exists in cache' do
      before do
        Rails.cache.write(
          "check_in.vaos_facility_#{facility_id}",
          facility_response,
          expires_in: 12.hours
        )
      end

      it 'returns facility data from cache' do
        response = subject.get_facility_with_cache(facility_id:)
        expect_any_instance_of(described_class).not_to receive(:perform)
        expect(response).to eq(facility_response)
      end
    end

    context 'when facility v3 cache is populated and facilities v3 flipper is enabled' do
      before do
        allow(Flipper).to receive(:enabled?).with(:check_in_experience_va_mobile_facilities_v3_enabled).and_return(true)
        Rails.cache.write(
          "check_in.vaos_facility_v3_#{facility_id}",
          facility_response,
          expires_in: 12.hours
        )
      end

      it 'returns facility data from v3 cache key without calling perform' do
        response = subject.get_facility_with_cache(facility_id:)
        expect_any_instance_of(described_class).not_to receive(:perform)
        expect(response).to eq(facility_response)
      end
    end

    context 'when clinic data exists in cache' do
      let(:clinic_response) do
        {
          data: {
            vistaSite: 534,
            clinicId: clinic_id,
            serviceName: 'CHS NEUROSURGERY VARMA',
            friendlyName: 'CHS NEUROSURGERY VARMA',
            stationId: '534',
            primaryStopCode: 406,
            primaryStopCodeName: 'NEUROSURGERY',
            patientDisplay: true,
            timezone: {
              timeZoneId: 'America/New_York'
            },
            futureBookingMaximumDays: 390
          }
        }
      end

      before do
        Rails.cache.write(
          "check_in.vaos_clinic_#{facility_id}_#{clinic_id}",
          clinic_response,
          expires_in: 12.hours
        )
      end

      it 'returns clinic data from cache' do
        response = subject.get_clinic_with_cache(facility_id:, clinic_id:)
        expect_any_instance_of(described_class).not_to receive(:perform)
        expect(response).to eq(clinic_response)
      end

      context 'when facilities v3 and VDS site info clinics are enabled and VDS clinic list is cached' do
        let(:facility_id) { '534' }
        let(:clinic_id) { '1081' }
        let(:facility) { { vistaSite: facility_id }.with_indifferent_access }
        let(:vds_clinics) do
          [
            {
              clinicIen: clinic_id,
              name: 'CHS NEUROSURGERY VARMA',
              friendlyName: 'CHS NEUROSURGERY VARMA',
              physicalLocation: '1ST FL SPECIALTY MODULE 2'
            }
          ]
        end
        let(:mapped_clinic_response) do
          {
            data: {
              clinicId: clinic_id,
              serviceName: 'CHS NEUROSURGERY VARMA',
              friendlyName: 'CHS NEUROSURGERY VARMA',
              physicalLocation: '1ST FL SPECIALTY MODULE 2'
            }
          }
        end

        before do
          allow(Flipper).to receive(:enabled?)
            .with(:check_in_experience_va_mobile_facilities_v3_enabled)
            .and_return(true)
          allow(Flipper).to receive(:enabled?)
            .with(:check_in_experience_vds_site_info_clinics_enabled)
            .and_return(true)
          Rails.cache.write(
            "check_in.vds_site_clinics_#{facility_id}",
            vds_clinics,
            expires_in: 12.hours
          )
        end

        it 'returns mapped clinic from VDS list cache without HTTP' do
          expect_any_instance_of(described_class).not_to receive(:perform)
          response = subject.get_clinic_with_cache(facility_id:, clinic_id:, facility:)
          expect(response).to eq(mapped_clinic_response.with_indifferent_access)
        end
      end

      context 'when facilities v3 is enabled without VDS site info clinics' do
        before do
          allow(Flipper).to receive(:enabled?)
            .with(:check_in_experience_va_mobile_facilities_v3_enabled)
            .and_return(true)
          Rails.cache.write(
            "check_in.vaos_clinic_#{facility_id}_#{clinic_id}",
            clinic_response,
            expires_in: 12.hours
          )
        end

        it 'returns nil without using cached MFS clinic payload' do
          expect_any_instance_of(described_class).not_to receive(:perform)
          expect(subject.get_clinic_with_cache(facility_id:, clinic_id:)).to be_nil
        end
      end
    end
  end

  describe 'enrichment failures degrade gracefully' do
    # Cached enrichment must never take down the appointments response, which has already been
    # fetched successfully. A failed facility/clinic lookup should return nil, not raise.
    let(:resp) { Faraday::Response.new(body: 'bad request', status: 400) }
    let(:exception) do
      Common::Exceptions::BackendServiceException.new('VAOS_400', { detail: 'bad request' }, resp.status, resp.body)
    end

    before { allow(StatsD).to receive(:increment) }

    # Captures the lazily-evaluated 'HCE-Check-In' log lines emitted while the block runs.
    def hce_logs_during
      logs = []
      allow(Rails.logger).to receive(:info) { |*_args, &block| logs << block.call if block }
      yield
      logs
    end

    context 'when the facility fetch returns a client error' do
      before do
        allow_any_instance_of(Faraday::Connection).to receive(:get).and_raise(exception)
      end

      it 'returns nil instead of raising' do
        expect(subject.get_facility_with_cache(facility_id:)).to be_nil
      end

      it 'increments the facility enrichment failure metric' do
        subject.get_facility_with_cache(facility_id:)
        expect(StatsD).to have_received(:increment)
          .with(CheckIn::Constants::STATSD_FACILITY_ENRICHMENT_FAILED)
      end

      it 'caches the miss so repeated lookups do not re-hit the upstream' do
        subject.get_facility_with_cache(facility_id:)
        subject.get_facility_with_cache(facility_id:)
        expect(StatsD).to have_received(:increment)
          .with(CheckIn::Constants::STATSD_FACILITY_ENRICHMENT_FAILED).once
      end

      it 'logs the upstream status, code, path, and likely cause' do
        logs = hce_logs_during { subject.get_facility_with_cache(facility_id:) }
        log = logs.find { |line| line.include?('enrichment_skipped') }

        expect(log).to include('appointments_facility_enrichment_skipped', "facility_id=#{facility_id}",
                               'facilities_version=v2', 'error=CheckIn::VAOS::ServiceException',
                               'code=VAOS_400', 'status=400',
                               'likely_cause=unrecognized_or_non_vista_facility')
      end
    end

    context 'when the facility lookup hits an open circuit breaker' do
      let(:outage_error) { Breakers::OutageException.new(nil, nil) }

      before do
        allow_any_instance_of(Faraday::Connection).to receive(:get).and_raise(outage_error)
      end

      it 'degrades to nil and logs the breaker as the likely cause' do
        logs = hce_logs_during { expect(subject.get_facility_with_cache(facility_id:)).to be_nil }
        log = logs.find { |line| line.include?('enrichment_skipped') }

        expect(log).to include('error=Breakers::OutageException', 'likely_cause=upstream_circuit_breaker_open')
        expect(StatsD).to have_received(:increment)
          .with(CheckIn::Constants::STATSD_FACILITY_ENRICHMENT_FAILED)
      end
    end

    context 'when the MFS clinic fetch returns a client error' do
      before do
        allow_any_instance_of(Faraday::Connection).to receive(:get).and_raise(exception)
      end

      it 'returns nil and increments the clinic enrichment failure metric' do
        expect(subject.get_clinic_with_cache(facility_id:, clinic_id:)).to be_nil
        expect(StatsD).to have_received(:increment)
          .with(CheckIn::Constants::STATSD_CLINIC_ENRICHMENT_FAILED)
      end
    end

    context 'when facility enrichment did not provide vistaSite for VDS clinic lookup' do
      let(:facility_id) { '983GC' }

      before do
        allow(Flipper).to receive(:enabled?)
          .with(:check_in_experience_va_mobile_facilities_v3_enabled).and_return(true)
        allow(Flipper).to receive(:enabled?)
          .with(:check_in_experience_vds_site_info_clinics_enabled).and_return(true)
      end

      it 'returns nil without calling VDS with the institution location id' do
        expect_any_instance_of(Faraday::Connection).not_to receive(:get)
        expect(subject.get_clinic_with_cache(facility_id:, clinic_id:)).to be_nil
      end

      it 'logs and metrics the missing vistaSite' do
        allow(StatsD).to receive(:increment)
        expect(Rails.logger).to receive(:info).with('HCE-Check-In')

        subject.get_clinic_with_cache(facility_id:, clinic_id:)

        expect(StatsD).to have_received(:increment).with(
          CheckIn::Constants::STATSD_VDS_SITE_INFO_CLINICS_VISTA_SITE_MISSING
        )
      end
    end

    context 'when the VDS clinic list fetch fails for a valid vista site' do
      let(:facility_id) { '983GC' }
      let(:facility) { { vistaSite: '983' }.with_indifferent_access }

      before do
        allow(Flipper).to receive(:enabled?)
          .with(:check_in_experience_va_mobile_facilities_v3_enabled).and_return(true)
        allow(Flipper).to receive(:enabled?)
          .with(:check_in_experience_vds_site_info_clinics_enabled).and_return(true)
        allow_any_instance_of(Faraday::Connection).to receive(:get)
          .with('/vds/info/v1/sites/983/clinics', {})
          .and_raise(exception)
      end

      it 'returns nil so the appointment is still rendered without clinic info' do
        expect(subject.get_clinic_with_cache(facility_id:, clinic_id:, facility:)).to be_nil
      end

      it 'increments the clinic enrichment failure metric' do
        subject.get_clinic_with_cache(facility_id:, clinic_id:, facility:)
        expect(StatsD).to have_received(:increment)
          .with(CheckIn::Constants::STATSD_CLINIC_ENRICHMENT_FAILED)
      end

      it 'caches the miss so the site is not re-fetched within the response' do
        subject.get_clinic_with_cache(facility_id:, clinic_id:, facility:)
        subject.get_clinic_with_cache(facility_id:, clinic_id:, facility:)
        expect(StatsD).to have_received(:increment)
          .with(CheckIn::Constants::STATSD_CLINIC_ENRICHMENT_FAILED).once
      end

      it 'logs the enrichment failure with VDS path context' do
        logs = hce_logs_during { subject.get_clinic_with_cache(facility_id:, clinic_id:, facility:) }
        log = logs.find { |line| line.include?('enrichment_skipped') }

        expect(log).to include('appointments_clinic_enrichment_skipped', 'facility_id=983GC',
                               "clinic_id=#{clinic_id}", 'facilities_version=v3', 'vds_clinics=enabled',
                               'code=VAOS_400', 'status=400',
                               'likely_cause=non_vista_site_or_unknown_clinic')
      end
    end
  end
end
