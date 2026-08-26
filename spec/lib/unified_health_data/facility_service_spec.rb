# frozen_string_literal: true

require 'rails_helper'
require 'unified_health_data/facility_service'

RSpec.describe UnifiedHealthData::FacilityService, type: :service do
  subject(:service) { described_class.new }

  describe '#get_facility_timezone' do
    context 'when station_number is blank' do
      it 'returns nil for nil' do
        expect(service.get_facility_timezone(nil)).to be_nil
      end

      it 'returns nil for empty string' do
        expect(service.get_facility_timezone('')).to be_nil
      end
    end

    context 'when facility is found with timezone' do
      before do
        stub_request(:get, %r{/facilities/v3/facilities/668})
          .to_return(
            status: 200,
            body: {
              id: '668',
              name: 'Mann-Grandstaff VA Medical Center',
              timezone: { zoneId: 'America/Los_Angeles' }
            }.to_json,
            headers: { 'Content-Type' => 'application/json' }
          )
      end

      it 'returns the timezone ID' do
        expect(service.get_facility_timezone('668')).to eq('America/Los_Angeles')
      end
    end

    context 'when facility is found without timezone' do
      before do
        stub_request(:get, %r{/facilities/v3/facilities/668})
          .to_return(
            status: 200,
            body: {
              id: '668',
              name: 'Mann-Grandstaff VA Medical Center'
            }.to_json,
            headers: { 'Content-Type' => 'application/json' }
          )
      end

      it 'returns nil' do
        expect(service.get_facility_timezone('668')).to be_nil
      end
    end

    context 'when facility is not found' do
      before do
        stub_request(:get, %r{/facilities/v3/facilities/999})
          .to_return(status: 404, body: { error: 'Not found' }.to_json)
        allow(Rails.logger).to receive(:warn)
      end

      it 'returns nil' do
        expect(service.get_facility_timezone('999')).to be_nil
      end
    end
  end

  describe '#get_facility_with_cache' do
    let(:facility_id) { '668' }
    let(:cache_key) { "uhd_facility_#{facility_id}" }

    before do
      stub_request(:get, %r{/facilities/v3/facilities/668})
        .to_return(
          status: 200,
          body: { id: '668', name: 'API Facility' }.to_json,
          headers: { 'Content-Type' => 'application/json' }
        )
    end

    it 'writes successful results to cache with the standard TTL' do
      expect(Rails.cache).to receive(:write)
        .with(cache_key, hash_including(id: '668'), expires_in: 12.hours)
        .and_call_original

      service.get_facility_with_cache(facility_id)
    end

    it 'returns facility data' do
      result = service.get_facility_with_cache(facility_id)
      expect(result[:id]).to eq('668')
    end

    it 'caches successful results and does not call API again' do
      allow(Rails).to receive(:cache).and_return(ActiveSupport::Cache::MemoryStore.new)

      service.get_facility_with_cache(facility_id)
      service.get_facility_with_cache(facility_id)

      expect(a_request(:get, %r{/facilities/v3/facilities/668})).to have_been_made.once
    end

    context 'when facility is not found' do
      before do
        stub_request(:get, %r{/facilities/v3/facilities/989})
          .to_return(status: 404, body: { error: 'Not found' }.to_json)
        allow(Rails.logger).to receive(:warn)
      end

      let(:facility_id) { '989' }
      let(:cache_key) { 'uhd_facility_989' }

      it 'returns nil' do
        expect(service.get_facility_with_cache(facility_id)).to be_nil
      end

      it 'caches the not-found sentinel with the shorter TTL' do
        expect(Rails.cache).to receive(:write)
          .with(cache_key, described_class::NOT_FOUND_SENTINEL, expires_in: 1.hour)
          .and_call_original

        service.get_facility_with_cache(facility_id)
      end

      it 'caches the not-found result and does not call API again' do
        allow(Rails).to receive(:cache).and_return(ActiveSupport::Cache::MemoryStore.new)

        service.get_facility_with_cache(facility_id)
        service.get_facility_with_cache(facility_id)

        expect(a_request(:get, %r{/facilities/v3/facilities/989})).to have_been_made.once
      end

      it 'returns nil (not the sentinel) when reading from cache' do
        cache = ActiveSupport::Cache::MemoryStore.new
        allow(Rails).to receive(:cache).and_return(cache)

        service.get_facility_with_cache(facility_id)

        expect(service.get_facility_with_cache(facility_id)).to be_nil
      end

      it 'caches when original_status is a string "404"' do
        error = Common::Exceptions::BackendServiceException.new('VA900', {}, '404')
        stub_request(:get, %r{/facilities/v3/facilities/989}).to_raise(error)
        expect(Rails.cache).to receive(:write)
          .with(cache_key, described_class::NOT_FOUND_SENTINEL, expires_in: 1.hour)

        service.get_facility_with_cache(facility_id)
      end
    end

    context 'when the API returns a transient error (5xx)' do
      before do
        stub_request(:get, %r{/facilities/v3/facilities/668})
          .to_return(status: 503, body: { error: 'Service unavailable' }.to_json)
        allow(Rails.logger).to receive(:warn)
      end

      it 'returns nil' do
        expect(service.get_facility_with_cache(facility_id)).to be_nil
      end

      it 'does not cache the failure' do
        expect(Rails.cache).not_to receive(:write)

        service.get_facility_with_cache(facility_id)
      end

      it 'retries on the next request (does not cache)' do
        allow(Rails).to receive(:cache).and_return(ActiveSupport::Cache::MemoryStore.new)

        service.get_facility_with_cache(facility_id)
        service.get_facility_with_cache(facility_id)

        expect(a_request(:get, %r{/facilities/v3/facilities/668})).to have_been_made.twice
      end
    end

    context 'when the request raises a non-HTTP error (timeout)' do
      before do
        stub_request(:get, %r{/facilities/v3/facilities/668}).to_timeout
        allow(Rails.logger).to receive(:warn)
      end

      it 'returns nil' do
        expect(service.get_facility_with_cache(facility_id)).to be_nil
      end

      it 'does not cache the failure' do
        expect(Rails.cache).not_to receive(:write)

        service.get_facility_with_cache(facility_id)
      end

      it 'retries on the next request (does not cache)' do
        allow(Rails).to receive(:cache).and_return(ActiveSupport::Cache::MemoryStore.new)

        service.get_facility_with_cache(facility_id)
        service.get_facility_with_cache(facility_id)

        expect(a_request(:get, %r{/facilities/v3/facilities/668})).to have_been_made.twice
      end
    end
  end

  describe '#get_facility' do
    let(:facility_id) { '983' }

    context 'when API returns success' do
      before do
        stub_request(:get, %r{/facilities/v3/facilities/983})
          .to_return(
            status: 200,
            body: {
              id: '983',
              name: 'Cheyenne VA Medical Center',
              timezone: { zoneId: 'America/Denver' }
            }.to_json,
            headers: { 'Content-Type' => 'application/json' }
          )
      end

      it 'returns facility data' do
        result = service.get_facility(facility_id)
        expect(result[:id]).to eq('983')
        expect(result[:timezone][:zoneId]).to eq('America/Denver')
      end
    end

    context 'when API returns error' do
      before do
        stub_request(:get, %r{/facilities/v3/facilities/999})
          .to_return(status: 404, body: { error: 'Not found' }.to_json)
      end

      it 'returns nil and logs warning' do
        expect(Rails.logger).to receive(:warn).with(
          /UHD FacilityService error/,
          hash_including(service: 'unified_health_data', facility_id: '999')
        )

        result = service.get_facility('999')
        expect(result).to be_nil
      end
    end

    context 'when API returns invalid JSON' do
      before do
        stub_request(:get, %r{/facilities/v3/facilities/668})
          .to_return(
            status: 200,
            body: 'not valid json {{{',
            headers: { 'Content-Type' => 'application/json' }
          )
      end

      it 'returns nil and logs warning' do
        expect(Rails.logger).to receive(:warn).with(
          /Failed to parse response body/,
          hash_including(service: 'unified_health_data')
        )

        result = service.get_facility('668')
        expect(result).to be_nil
      end
    end
  end
end
