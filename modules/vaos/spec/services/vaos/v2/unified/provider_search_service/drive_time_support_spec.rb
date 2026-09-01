# frozen_string_literal: true

require 'rails_helper'

RSpec.describe VAOS::V2::Unified::ProviderSearchService::DriveTimeSupport do
  # The module is a private mixin for ProviderSearchService. These specs exercise it
  # in isolation through a minimal host that supplies the same collaborators the real
  # service provides (current_user, eps_provider_service, coerce_float, log_prefix,
  # @cached_user_uuid). The integration path is covered by provider_search_service_spec.
  let(:host_class) do
    Class.new do
      include VAOS::V2::Unified::ProviderSearchService::DriveTimeSupport
      include VAOS::V2::Unified::ProviderSearchService::EpsDriveTimeSupport
      include VAOS::V2::Unified::ProviderSearchService::VADriveTimeSupport

      attr_reader :current_user, :eps_provider_service, :lighthouse_nearby_client

      def initialize(current_user:, eps_provider_service:, lighthouse_nearby_client: nil)
        @current_user = current_user
        @eps_provider_service = eps_provider_service
        @lighthouse_nearby_client = lighthouse_nearby_client
        @cached_user_uuid = current_user&.uuid
      end

      # Mirrors the shared coercion helper that stays on the service class.
      def coerce_float(value)
        Float(value)
      rescue ArgumentError, TypeError
        nil
      end

      def log_prefix
        'Test: Unified Provider Search'
      end
    end
  end

  let(:user) { double('User', uuid: 'user-uuid-123') }
  let(:eps_provider_service) { instance_double(Eps::ProviderService) }
  let(:lighthouse_nearby_client) { instance_double(FacilitiesApi::V2::Lighthouse::NearbyClient) }
  let(:host) { host_class.new(current_user: user, eps_provider_service:, lighthouse_nearby_client:) }
  let(:user_address) { double('Address', latitude: 28.08, longitude: -80.60) }

  # Stand-in for a unified provider: responds to lat/long, a Lighthouse facility id
  # (used by VA drive-time matching), a provider id (logged for unmatched EPS providers),
  # and a writable drive time.
  def build_provider(latitude, longitude, facility_id: nil, id: nil)
    Struct.new(:latitude, :longitude, :facility_id, :id, :drive_time_in_seconds)
          .new(latitude, longitude, facility_id, id, nil)
  end

  def drive_times_response(destinations)
    Struct.new(:destinations).new(destinations)
  end

  # Stand-in for a VA Facilities NearbyFacility (id + drive-time band in minutes).
  def nearby_facility(id, min_time, max_time)
    Struct.new(:id, :min_time, :max_time).new(id, min_time, max_time)
  end

  describe '#drive_time_enrichment_enabled?' do
    it 'is true when the flag is on for the user' do
      allow(Flipper).to receive(:enabled?)
        .with(:va_online_scheduling_unified_drive_time, user).and_return(true)

      expect(host.send(:drive_time_enrichment_enabled?)).to be(true)
    end

    it 'is false when the flag is off for the user' do
      allow(Flipper).to receive(:enabled?)
        .with(:va_online_scheduling_unified_drive_time, user).and_return(false)

      expect(host.send(:drive_time_enrichment_enabled?)).to be(false)
    end
  end

  describe '#start_eps_drive_time_enrichment' do
    let(:eps_providers) { [build_provider(28.08061, -80.60322)] }

    it 'returns nil when there are no EPS providers' do
      expect(host.send(:start_eps_drive_time_enrichment, [], user_address)).to be_nil
    end

    it 'returns nil when the flag is off (no future spawned, no EPS call)' do
      allow(Flipper).to receive(:enabled?)
        .with(:va_online_scheduling_unified_drive_time, user).and_return(false)
      allow(eps_provider_service).to receive(:get_drive_times)

      expect(host.send(:start_eps_drive_time_enrichment, eps_providers, user_address)).to be_nil
      expect(eps_provider_service).not_to have_received(:get_drive_times)
    end

    it 'returns a future resolving to the coordinate=>seconds map when enabled' do
      allow(Flipper).to receive(:enabled?)
        .with(:va_online_scheduling_unified_drive_time, user).and_return(true)
      allow(eps_provider_service).to receive(:get_drive_times)
        .and_return(drive_times_response(d0: { drive_time_in_seconds_without_traffic: 420 }))

      future = host.send(:start_eps_drive_time_enrichment, eps_providers, user_address)

      expect(future.value!).to eq({ [28.08061, -80.60322] => 420 })
    end
  end

  describe '#fetch_drive_times_by_coordinates' do
    before do
      allow(eps_provider_service).to receive(:get_drive_times)
        .and_return(drive_times_response(
                      d0: { drive_time_in_seconds_without_traffic: 420 },
                      d1: { drive_time_in_seconds_without_traffic: 900 }
                    ))
    end

    it 'sends one batched destination per unique coordinate and maps the response back' do
      providers = [build_provider(28.08061, -80.60322), build_provider(29.0, -81.0)]

      result = host.send(:fetch_drive_times_by_coordinates, providers, user_address)

      expect(eps_provider_service).to have_received(:get_drive_times).with(
        destinations: {
          'd0' => { latitude: 28.08061, longitude: -80.60322 },
          'd1' => { latitude: 29.0, longitude: -81.0 }
        },
        origin: { latitude: 28.08, longitude: -80.60 }
      )
      expect(result).to eq({ [28.08061, -80.60322] => 420, [29.0, -81.0] => 900 })
    end

    it 'de-duplicates identical coordinates into a single destination' do
      providers = [build_provider(28.08061, -80.60322), build_provider(28.08061, -80.60322)]

      host.send(:fetch_drive_times_by_coordinates, providers, user_address)

      expect(eps_provider_service).to have_received(:get_drive_times).with(
        hash_including(destinations: { 'd0' => { latitude: 28.08061, longitude: -80.60322 } })
      )
    end

    it 'coerces stringified seconds to an integer' do
      allow(eps_provider_service).to receive(:get_drive_times)
        .and_return(drive_times_response(d0: { drive_time_in_seconds_without_traffic: '420' }))
      providers = [build_provider(28.08061, -80.60322)]

      result = host.send(:fetch_drive_times_by_coordinates, providers, user_address)

      expect(result).to eq({ [28.08061, -80.60322] => 420 })
    end

    it 'returns an empty map and makes no call when no provider has usable coordinates' do
      providers = [build_provider(nil, nil), build_provider('not-a-number', -80.60322)]

      expect(host.send(:fetch_drive_times_by_coordinates, providers, user_address)).to eq({})
      expect(eps_provider_service).not_to have_received(:get_drive_times)
    end
  end

  describe '#apply_eps_drive_times!' do
    let(:providers) { [build_provider(28.08061, -80.60322), build_provider(29.0, -81.0)] }

    it 'no-ops when the future is nil (flag off / no EPS providers)' do
      expect { host.send(:apply_eps_drive_times!, providers, nil) }.not_to raise_error
      expect(providers.map(&:drive_time_in_seconds)).to all(be_nil)
    end

    it 'writes drive_time_in_seconds onto each provider by coordinate' do
      future = Concurrent::Promises.fulfilled_future(
        { [28.08061, -80.60322] => 420, [29.0, -81.0] => 900 }
      )

      host.send(:apply_eps_drive_times!, providers, future)

      expect(providers.map(&:drive_time_in_seconds)).to eq([420, 900])
    end

    it 'leaves a provider nil when its coordinate is absent from the result map' do
      future = Concurrent::Promises.fulfilled_future({ [28.08061, -80.60322] => 420 })

      host.send(:apply_eps_drive_times!, providers, future)

      expect(providers.map(&:drive_time_in_seconds)).to eq([420, nil])
    end

    it 'fails open and logs a warning when the future rejects' do
      allow(Rails.logger).to receive(:warn)
      future = Concurrent::Promises.rejected_future(StandardError.new('boom'))

      expect { host.send(:apply_eps_drive_times!, providers, future) }.not_to raise_error
      expect(providers.map(&:drive_time_in_seconds)).to all(be_nil)
      expect(Rails.logger).to have_received(:warn)
        .with(/drive-time enrichment failed/, hash_including(source: 'eps', user_uuid: 'user-uuid-123'))
    end

    it 'waits on the future with the configured timeout' do
      future = instance_double(Concurrent::Promises::Future, value!: {})

      host.send(:apply_eps_drive_times!, providers, future)

      expect(future).to have_received(:value!).with(a_kind_of(Numeric))
    end

    it 'fails open and emits a timeout metric when the future times out (value! returns nil)' do
      allow(Rails.logger).to receive(:warn)
      allow(StatsD).to receive(:increment)
      # value!(timeout) returns nil on timeout without raising or cancelling the work.
      future = instance_double(Concurrent::Promises::Future, value!: nil)

      expect { host.send(:apply_eps_drive_times!, providers, future) }.not_to raise_error
      expect(providers.map(&:drive_time_in_seconds)).to all(be_nil)
      expect(Rails.logger).to have_received(:warn)
        .with(/drive-time enrichment timed out/, hash_including(source: 'eps', user_uuid: 'user-uuid-123'))
      expect(StatsD).to have_received(:increment)
        .with('api.vaos.unified_provider_search.drive_time_enrichment.timeout', tags: ['source:eps'])
    end
  end

  describe '#drive_time_timeout_seconds' do
    it 'reads the positive Settings value' do
      allow(Settings.vaos.unified_scheduling).to receive(:drive_time_timeout_seconds).and_return('5')

      expect(host.send(:drive_time_timeout_seconds)).to eq(5.0)
    end

    it 'falls back to the default for a non-positive value' do
      allow(Settings.vaos.unified_scheduling).to receive(:drive_time_timeout_seconds).and_return(0)

      expect(host.send(:drive_time_timeout_seconds))
        .to eq(described_class::DEFAULT_DRIVE_TIME_TIMEOUT_SECONDS)
    end

    it 'falls back and emits an ops-visible signal when the value is unparseable' do
      allow(Rails.logger).to receive(:warn)
      allow(StatsD).to receive(:increment)
      allow(Settings.vaos.unified_scheduling).to receive(:drive_time_timeout_seconds).and_return('abc')

      expect(host.send(:drive_time_timeout_seconds))
        .to eq(described_class::DEFAULT_DRIVE_TIME_TIMEOUT_SECONDS)
      expect(Rails.logger).to have_received(:warn).with(/invalid_setting/, hash_including(error_class: 'ArgumentError'))
      expect(StatsD).to have_received(:increment)
        .with('api.vaos.unified_provider_search.drive_time_timeout.invalid_setting',
              tags: ['error_class:ArgumentError'])
    end
  end

  describe '#join_drive_times_future' do
    before do
      allow(Settings.vaos.unified_scheduling).to receive(:drive_time_timeout_seconds).and_return('5')
    end

    it 'returns the resolved map and emits no timeout signal when the wait completes' do
      allow(Rails.logger).to receive(:warn)
      allow(StatsD).to receive(:increment)
      future = instance_double(Concurrent::Promises::Future, value!: { [28.08061, -80.60322] => 420 })

      result = host.send(:join_drive_times_future, 'eps', future)

      expect(result).to eq({ [28.08061, -80.60322] => 420 })
      expect(future).to have_received(:value!).with(5.0)
      expect(Rails.logger).not_to have_received(:warn).with(/timed out/, anything)
      expect(StatsD).not_to have_received(:increment)
        .with('api.vaos.unified_provider_search.drive_time_enrichment.timeout', anything)
    end

    it 'returns nil and logs a timeout when the wait times out (value! returns nil)' do
      allow(Rails.logger).to receive(:warn)
      allow(StatsD).to receive(:increment)
      # value!(timeout) returns nil on timeout without raising or cancelling the work.
      future = instance_double(Concurrent::Promises::Future, value!: nil)

      result = host.send(:join_drive_times_future, 'eps', future)

      expect(result).to be_nil
      expect(Rails.logger).to have_received(:warn)
        .with(/drive-time enrichment timed out/,
              hash_including(source: 'eps', timeout_seconds: 5.0, user_uuid: 'user-uuid-123'))
      expect(StatsD).to have_received(:increment)
        .with('api.vaos.unified_provider_search.drive_time_enrichment.timeout', tags: ['source:eps'])
    end
  end

  describe '#start_va_drive_time_enrichment' do
    let(:va_providers) { [build_provider(41.14, -104.78, facility_id: 'vha_630')] }

    it 'returns nil when there are no VA providers' do
      expect(host.send(:start_va_drive_time_enrichment, [], user_address)).to be_nil
    end

    it 'returns nil when the flag is off (no future spawned, no nearby call)' do
      allow(Flipper).to receive(:enabled?)
        .with(:va_online_scheduling_unified_drive_time, user).and_return(false)
      allow(lighthouse_nearby_client).to receive(:nearby)

      expect(host.send(:start_va_drive_time_enrichment, va_providers, user_address)).to be_nil
      expect(lighthouse_nearby_client).not_to have_received(:nearby)
    end

    it 'returns a future resolving to the facility_id=>seconds map when enabled' do
      allow(Flipper).to receive(:enabled?)
        .with(:va_online_scheduling_unified_drive_time, user).and_return(true)
      allow(lighthouse_nearby_client).to receive(:nearby)
        .and_return([nearby_facility('vha_630', 10, 20)])

      future = host.send(:start_va_drive_time_enrichment, va_providers, user_address)

      expect(future.value!).to eq({ 'vha_630' => 900 })
    end
  end

  describe '#fetch_va_drive_times_by_facility' do
    it 'sends one origin call and maps each facility to its band midpoint in seconds' do
      allow(lighthouse_nearby_client).to receive(:nearby)
        .and_return([nearby_facility('vha_630', 10, 20), nearby_facility('vha_526GD', 20, 30)])

      result = host.send(:fetch_va_drive_times_by_facility, user_address)

      expect(lighthouse_nearby_client).to have_received(:nearby).with(lat: 28.08, long: -80.60)
      expect(result).to eq({ 'vha_630' => 900, 'vha_526GD' => 1500 })
    end

    it 'drops facilities missing a band bound' do
      allow(lighthouse_nearby_client).to receive(:nearby)
        .and_return([nearby_facility('vha_630', 10, 20), nearby_facility('vha_526GD', nil, 30)])

      result = host.send(:fetch_va_drive_times_by_facility, user_address)

      expect(result).to eq({ 'vha_630' => 900 })
    end
  end

  describe '#apply_va_drive_times!' do
    let(:providers) do
      [build_provider(41.14, -104.78, facility_id: 'vha_630'),
       build_provider(39.74, -104.99, facility_id: 'vha_554')]
    end

    it 'no-ops when the future is nil (flag off / no VA providers)' do
      expect { host.send(:apply_va_drive_times!, providers, nil) }.not_to raise_error
      expect(providers.map(&:drive_time_in_seconds)).to all(be_nil)
    end

    it 'writes drive_time_in_seconds onto each provider by facility id' do
      future = Concurrent::Promises.fulfilled_future({ 'vha_630' => 900, 'vha_554' => 1500 })

      host.send(:apply_va_drive_times!, providers, future)

      expect(providers.map(&:drive_time_in_seconds)).to eq([900, 1500])
    end

    it 'leaves a provider nil when its facility is absent from the result map' do
      future = Concurrent::Promises.fulfilled_future({ 'vha_630' => 900 })

      host.send(:apply_va_drive_times!, providers, future)

      expect(providers.map(&:drive_time_in_seconds)).to eq([900, nil])
    end

    it 'fails open and logs a warning when the future rejects' do
      allow(Rails.logger).to receive(:warn)
      future = Concurrent::Promises.rejected_future(StandardError.new('boom'))

      expect { host.send(:apply_va_drive_times!, providers, future) }.not_to raise_error
      expect(providers.map(&:drive_time_in_seconds)).to all(be_nil)
      expect(Rails.logger).to have_received(:warn)
        .with(/drive-time enrichment failed/, hash_including(source: 'va', user_uuid: 'user-uuid-123'))
    end

    it 'waits on the future with the configured timeout' do
      future = instance_double(Concurrent::Promises::Future, value!: {})

      host.send(:apply_va_drive_times!, providers, future)

      expect(future).to have_received(:value!).with(a_kind_of(Numeric))
    end

    it 'fails open and emits a timeout metric when the future times out (value! returns nil)' do
      allow(Rails.logger).to receive(:warn)
      allow(StatsD).to receive(:increment)
      # value!(timeout) returns nil on timeout without raising or cancelling the work.
      future = instance_double(Concurrent::Promises::Future, value!: nil)

      expect { host.send(:apply_va_drive_times!, providers, future) }.not_to raise_error
      expect(providers.map(&:drive_time_in_seconds)).to all(be_nil)
      expect(Rails.logger).to have_received(:warn)
        .with(/drive-time enrichment timed out/, hash_including(source: 'va', user_uuid: 'user-uuid-123'))
      expect(StatsD).to have_received(:increment)
        .with('api.vaos.unified_provider_search.drive_time_enrichment.timeout', tags: ['source:va'])
    end
  end

  describe '#apply_drive_times_in_parallel!' do
    let(:va_providers) { [build_provider(41.14, -104.78, facility_id: 'vha_630')] }
    let(:eps_providers) { [build_provider(28.08061, -80.60322, id: 'eps-1')] }

    it 'applies both sources when each join completes' do
      va_future = Concurrent::Promises.fulfilled_future({ 'vha_630' => 900 })
      eps_future = Concurrent::Promises.fulfilled_future({ [28.08061, -80.60322] => 420 })

      host.send(:apply_drive_times_in_parallel!, va_providers, va_future, eps_providers, eps_future)

      expect(va_providers.first.drive_time_in_seconds).to eq(900)
      expect(eps_providers.first.drive_time_in_seconds).to eq(420)
    end

    # The case the outer deadline exists for: a waiter that never completes because the
    # apply itself is blocked (or the pool never schedules it). The inner per-source
    # timeout can't cover this -- it is never reached -- so without the outer bound the
    # request thread would hang. The unaffected source must still land its drive times.
    it 'returns instead of hanging when a waiter never completes, leaving that source nil' do
      allow(host).to receive(:drive_time_timeout_seconds).and_return(0.5)
      stub_const("#{described_class}::OUTER_JOIN_HEADROOM_SECONDS", 0)
      blocked = Concurrent::CountDownLatch.new(1)
      allow(host).to receive(:apply_va_drive_times!) { blocked.wait(10) }
      va_future = Concurrent::Promises.fulfilled_future({ 'vha_630' => 900 })
      eps_future = Concurrent::Promises.fulfilled_future({ [28.08061, -80.60322] => 420 })

      expect do
        Timeout.timeout(10) do
          host.send(:apply_drive_times_in_parallel!, va_providers, va_future, eps_providers, eps_future)
        end
      end.not_to raise_error

      expect(va_providers.first.drive_time_in_seconds).to be_nil
      expect(eps_providers.first.drive_time_in_seconds).to eq(420)
    ensure
      blocked&.count_down
    end
  end

  describe 'drive-time coverage signal (via #apply_*_drive_times!)' do
    let(:prefix) { 'api.vaos.unified_provider_search.drive_time_enrichment' }

    before { allow(StatsD).to receive(:increment) }

    context 'EPS' do
      let(:providers) do
        [build_provider(28.08061, -80.60322, id: 'eps-1'), build_provider(29.0, -81.0, id: 'eps-2')]
      end

      it 'emits provider_count and no missing metric or warn when every provider matches' do
        allow(Rails.logger).to receive(:warn)
        future = Concurrent::Promises.fulfilled_future(
          { [28.08061, -80.60322] => 420, [29.0, -81.0] => 900 }
        )

        host.send(:apply_eps_drive_times!, providers, future)

        expect(StatsD).to have_received(:increment).with("#{prefix}.provider_count", 2, tags: ['source:eps'])
        expect(StatsD).not_to have_received(:increment).with("#{prefix}.missing", anything, anything)
        expect(Rails.logger).not_to have_received(:warn)
      end

      it 'emits the missing metric and warns with unmatched provider ids' do
        allow(Rails.logger).to receive(:warn)
        future = Concurrent::Promises.fulfilled_future({ [28.08061, -80.60322] => 420 })

        host.send(:apply_eps_drive_times!, providers, future)

        expect(StatsD).to have_received(:increment).with("#{prefix}.provider_count", 2, tags: ['source:eps'])
        expect(StatsD).to have_received(:increment).with("#{prefix}.missing", 1, tags: ['source:eps'])
        expect(Rails.logger).to have_received(:warn).with(
          /drive-time enrichment incomplete/,
          hash_including(source: 'eps', missing_count: 1, provider_count: 2,
                         missing_ids: ['eps-2'], user_uuid: 'user-uuid-123')
        )
      end
    end

    context 'VA' do
      let(:providers) do
        [build_provider(41.14, -104.78, facility_id: 'vha_630'),
         build_provider(39.74, -104.99, facility_id: 'vha_554')]
      end

      it 'emits the missing metric and warns with unmatched facility ids' do
        allow(Rails.logger).to receive(:warn)
        future = Concurrent::Promises.fulfilled_future({ 'vha_630' => 900 })

        host.send(:apply_va_drive_times!, providers, future)

        expect(StatsD).to have_received(:increment).with("#{prefix}.provider_count", 2, tags: ['source:va'])
        expect(StatsD).to have_received(:increment).with("#{prefix}.missing", 1, tags: ['source:va'])
        expect(Rails.logger).to have_received(:warn).with(
          /drive-time enrichment incomplete/,
          hash_including(source: 'va', missing_count: 1, provider_count: 2,
                         missing_ids: ['vha_554'], user_uuid: 'user-uuid-123')
        )
      end
    end

    it 'does not record coverage on the timeout path (value! returns nil)' do
      future = instance_double(Concurrent::Promises::Future, value!: nil)

      host.send(:apply_va_drive_times!, [build_provider(41.14, -104.78, facility_id: 'vha_630')], future)

      expect(StatsD).not_to have_received(:increment).with(/provider_count/, anything, anything)
    end

    it 'caps the logged missing id sample at MAX_LOGGED_MISSING_IDS while keeping an exact count' do
      allow(Rails.logger).to receive(:warn)
      cap = described_class::MAX_LOGGED_MISSING_IDS
      providers = Array.new(cap + 5) { |i| build_provider(28.0 + i, -80.0, id: "eps-#{i}") }
      future = Concurrent::Promises.fulfilled_future({})

      host.send(:apply_eps_drive_times!, providers, future)

      expect(Rails.logger).to have_received(:warn).with(
        /drive-time enrichment incomplete/,
        hash_including(missing_count: cap + 5,
                       missing_ids: satisfy { |ids| ids.size == cap })
      )
    end
  end

  describe '#coerce_integer' do
    it 'rounds decimal strings and floats' do
      expect(host.send(:coerce_integer, '420.5')).to eq(421)
      expect(host.send(:coerce_integer, 419.4)).to eq(419)
    end

    it 'reads zero-padded strings as decimal, not octal' do
      expect(host.send(:coerce_integer, '0420')).to eq(420)
    end

    it 'returns nil for nil or non-numeric input' do
      expect(host.send(:coerce_integer, nil)).to be_nil
      expect(host.send(:coerce_integer, 'abc')).to be_nil
    end
  end
end
