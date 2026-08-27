# frozen_string_literal: true

require 'rails_helper'
require 'debt_management_center/debts_service'
require 'debt_management_center/models/debt_store'
require_relative 'shared_examples/debt_service_examples'

RSpec.describe DebtManagementCenter::DebtsService do
  let(:file_number) { '796043735' }
  let(:user) { build(:user, :loa3, ssn: file_number) }
  let(:user_no_ssn) { build(:user, :loa3, ssn: '') }

  def with_vcr_cassettes(&)
    VCR.use_cassette('bgs/people_service/person_data') do
      VCR.use_cassette('debts/get_letters', VCR::MATCH_EVERYTHING, &)
    end
  end

  describe '#get_debts' do
    it_behaves_like 'debt service behavior'
  end

  describe '#get_debt_by_id' do
    let(:user) { build(:user, :loa3) }
    let(:debt_id) { '944147b0-7ec0-4a81-ab40-a437b5ce5353' }

    before do
      allow(StatsD).to receive(:increment)
    end

    context 'when debt is missing from redis' do
      it 'raises an error' do
        with_vcr_cassettes do
          service = described_class.new(user)

          expect { service.get_debt_by_id(debt_id) }.to raise_error(described_class::DebtNotFound)

          expect(StatsD).to have_received(:increment).with("#{described_class::STATSD_KEY_PREFIX}.get_debt.total")
          expect(StatsD).to have_received(:increment).with("#{described_class::STATSD_KEY_PREFIX}.get_debt.failure")
        end
      end
    end

    context 'with logged in user' do
      it 'downloads the pdf' do
        with_vcr_cassettes do
          service = described_class.new(user)
          debts = service.get_debts[:debts]
          debts.map { |d| d['id'] = SecureRandom.uuid }
          debts[0]['id'] = debt_id
          DebtManagementCenter::DebtStore.find_or_build(user.uuid).update(debts:, uuid: user.uuid)

          expect(service.get_debt_by_id(debt_id).to_json).to eq(get_fixture('dmc/debt').to_json)

          expect(StatsD).to have_received(:increment).with("#{described_class::STATSD_KEY_PREFIX}.get_debt.total")
          expect(StatsD).to have_received(:increment).with("#{described_class::STATSD_KEY_PREFIX}.get_debt.success")
        end
      end
    end
  end

  describe '#find_cdids_in_debts' do
    let(:user) { build(:user, :loa3) }
    let(:service) { described_class.new(user) }

    before do
      with_vcr_cassettes do
        service.get_debts # Load and process debts
      end
    end

    context 'with valid composite debt IDs' do
      it 'returns requested debts and empty missing_ids array' do
        cdid = service.get_debts[:debts].first['compositeDebtId']
        requested_debts, missing_ids = service.send(:find_cdids_in_debts, [cdid])
        expect(requested_debts.length).to eq(1)
        expect(requested_debts.first['compositeDebtId']).to eq(cdid)
        expect(missing_ids).to be_empty
      end

      it 'returns multiple debts when multiple IDs are provided' do
        cdids = service.get_debts[:debts].map { |d| d['compositeDebtId'] }.compact.uniq
        next unless cdids.length >= 2

        requested_debts, missing_ids = service.send(:find_cdids_in_debts, cdids.first(2))
        expect(requested_debts.length).to eq(2)
        expect(requested_debts.map { |d| d['compositeDebtId'] }).to match_array(cdids.first(2))
        expect(missing_ids).to be_empty
      end
    end

    context 'when some composite debt IDs are missing' do
      it 'returns found debts and missing IDs separately' do
        cdid = service.get_debts[:debts].first['compositeDebtId']
        requested_debts, missing_ids = service.send(:find_cdids_in_debts, [cdid, '999999'])
        expect(requested_debts.length).to eq(1)
        expect(requested_debts.first['compositeDebtId']).to eq(cdid)
        expect(missing_ids).to eq(['999999'])
      end
    end

    context 'with empty array' do
      it 'returns empty arrays for both debts and missing_ids' do
        requested_debts, missing_ids = service.send(:find_cdids_in_debts, [])
        expect(requested_debts).to be_empty
        expect(missing_ids).to be_empty
      end
    end

    context 'with duplicate composite debt IDs' do
      it 'returns the debt once for each duplicate ID' do
        cdid = service.get_debts[:debts].first['compositeDebtId']
        requested_debts, missing_ids = service.send(:find_cdids_in_debts, [cdid, cdid])
        expect(requested_debts.length).to eq(2)
        expect(requested_debts.map { |d| d['compositeDebtId'] }).to all(eq(cdid))
        expect(missing_ids).to be_empty
      end
    end
  end

  describe '#get_debts_by_ids' do
    let(:user) { build(:user, :loa3) }
    let(:service) { described_class.new(user) }

    before do
      allow(StatsD).to receive(:increment)
    end

    context 'when debts are not yet loaded' do
      it 'loads debts automatically before lookup' do
        VCR.use_cassette('bgs/people_service/person_data') do
          VCR.use_cassette('debts/get_letters', allow_playback_repeats: true) do
            cdid = service.get_debts[:debts].first['compositeDebtId']
            new_service = described_class.new(user)
            expect(new_service.instance_variable_get(:@debts)).to be_nil
            result = new_service.get_debts_by_ids([cdid])
            expect(result.length).to eq(1)
            expect(new_service.instance_variable_get(:@debts)).not_to be_nil
          end
        end
      end
    end

    context 'when some composite debt IDs are missing' do
      it 'logs warning with correct parameters' do
        with_vcr_cassettes do
          cdid = service.get_debts[:debts].first['compositeDebtId']
          expect(Rails.logger).to receive(:warn).with('DebtsService#get_debts_by_ids: Missing composite_debt_ids',
                                                      hash_including(requested_count: 2, found_count: 1))
          expect(StatsD).to receive(:increment).with(
            "#{described_class::STATSD_KEY_PREFIX}.get_debts_by_ids.missing_ids", tags: ['missing_count:1']
          )
          expect(StatsD).to receive(:increment).with("#{described_class::STATSD_KEY_PREFIX}.get_debt.success")
          service.get_debts_by_ids([cdid, '999999'])
        end
      end
    end

    context 'with successful lookup' do
      it 'increments success metric and does not log warning' do
        with_vcr_cassettes do
          cdid = service.get_debts[:debts].first['compositeDebtId']
          expect(Rails.logger).not_to receive(:warn)
          service.get_debts_by_ids([cdid])
          expect(StatsD).not_to have_received(:increment).with(
            "#{described_class::STATSD_KEY_PREFIX}.get_debts_by_ids.missing_ids", anything
          )
          expect(StatsD).to have_received(:increment).with("#{described_class::STATSD_KEY_PREFIX}.get_debt.success")
        end
      end
    end
  end

  describe '#fetch_debts_from_dmc' do
    subject(:fetch_debts) { service.send(:fetch_debts_from_dmc) }

    let(:service) { described_class.new(user) }
    let(:user) { build(:user, :loa3, ssn:) }
    let(:ssn) { '123456789' }
    let(:bgs_request) { instance_double(BGS::People::Request) }
    let(:bgs_response) { instance_double(BGS::People::Response, file_number:) }
    let(:file_number) { '12345678' }
    let(:response) { instance_double(Faraday::Response, body: []) }

    before do
      allow(BGS::People::Request).to receive(:new).and_return(bgs_request)
      allow(bgs_request).to receive(:find_person_by_participant_id).with(user:).and_return(bgs_response)
    end

    context 'with a valid file number' do
      before do
        expect(service).to receive(:perform).with(
          :post,
          Settings.dmc.debts_endpoint,
          { fileNumber: '12345678' },
          nil,
          { timeout: 30 }
        ).and_return(response)
      end

      it 'returns the debts' do
        expect(fetch_debts).to eq([])
      end
    end

    context 'when the file number is blank' do
      let(:file_number) { nil }
      let(:ssn) { '' }

      before do
        expect(service).to receive(:perform).with(
          :post,
          Settings.dmc.debts_endpoint,
          { fileNumber: '' },
          nil,
          { timeout: 30 }
        ).and_return(response)
      end

      it 'falls back to the SSN in the DMC request payload' do
        expect(fetch_debts).to eq([])
      end
    end
  end

  describe 'response caching' do
    let(:memory_store) { ActiveSupport::Cache.lookup_store(:memory_store) }
    let(:cache_key) { "debts_data_#{user.uuid}" }
    let(:statsd_prefix) { described_class::STATSD_KEY_PREFIX }

    before do
      allow(Rails).to receive(:cache).and_return(memory_store)
      allow(StatsD).to receive(:increment)
      allow(Flipper).to receive(:enabled?).and_call_original
    end

    # Flag-independent: the type guard and the empty check both short-circuit
    # before the flag is consulted.
    it 'refuses to cache anything that is not an array' do
      service = VCR.use_cassette('bgs/people_service/person_data') { described_class.new(user) }

      expect(service.send(:cache_response?, { 'debtsCount' => 3 })).to be(false)
      expect(service.send(:cache_response?, nil)).to be(false)
      expect(service.send(:cache_response?, [])).to be(true)
    end

    it 'does not touch the cache for a count-only request' do
      VCR.use_cassette('bgs/people_service/person_data') do
        VCR.use_cassette('debts/get_letters_count_only', VCR::MATCH_EVERYTHING) do
          described_class.new(user).get_debts(count_only: true)
        end
      end

      expect(Rails.cache.read(cache_key)).to be_nil
    end

    # Characterizes behavior that predates the debts_cache_dmc_full_response
    # flag. These must keep passing while the flag is off.
    context 'with debts_cache_dmc_full_response disabled' do
      before do
        allow(Flipper).to receive(:enabled?).with(:debts_cache_dmc_full_response, user).and_return(false)
      end

      it 'does not cache a non-empty response' do
        with_vcr_cassettes { described_class.new(user).get_debts }

        expect(Rails.cache.read(cache_key)).to be_nil
      end

      it 'caches an empty response' do
        VCR.use_cassette('bgs/people_service/person_data') do
          VCR.use_cassette('debts/get_letters_empty_response', VCR::MATCH_EVERYTHING) do
            described_class.new(user).get_debts
          end
        end

        expect(Rails.cache.read(cache_key)).to eq([])
        expect(StatsD).to have_received(:increment)
          .with("#{statsd_prefix}.init_cached_debts.response_cached", tags: ['type:empty'])
      end

      it 'returns a cached response without calling DMC' do
        Rails.cache.write(cache_key, [])

        VCR.use_cassette('bgs/people_service/person_data') do
          expect(described_class.new(user).get_debts[:debts]).to eq([])
        end

        expect(StatsD).to have_received(:increment).with("#{statsd_prefix}.init_cached_debts.cached_response_returned")
      end
    end

    context 'with debts_cache_dmc_full_response enabled' do
      before do
        allow(Flipper).to receive(:enabled?).with(:debts_cache_dmc_full_response, user).and_return(true)
      end

      it 'caches a non-empty response' do
        with_vcr_cassettes { described_class.new(user).get_debts }

        expect(Rails.cache.read(cache_key)).to be_an(Array)
        expect(Rails.cache.read(cache_key)).not_to be_empty
        expect(StatsD).to have_received(:increment)
          .with("#{statsd_prefix}.init_cached_debts.response_cached", tags: ['type:full'])
      end

      it 'serves the cached debts on a subsequent call' do
        with_vcr_cassettes { described_class.new(user).get_debts }

        VCR.use_cassette('bgs/people_service/person_data') do
          expect(described_class.new(user).get_debts[:debts]).to be_present
        end

        expect(StatsD).to have_received(:increment).with("#{statsd_prefix}.init_cached_debts.cached_response_returned")
      end
    end
  end
end
