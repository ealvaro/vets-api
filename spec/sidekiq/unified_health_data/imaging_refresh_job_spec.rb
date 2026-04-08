# frozen_string_literal: true

require 'rails_helper'
require 'unified_health_data/imaging_service'

Sidekiq::Testing.fake!

RSpec.describe UnifiedHealthData::ImagingRefreshJob, type: :job do
  let(:user) { create(:user, :loa3) }
  let(:imaging_service) { instance_double(UnifiedHealthData::ImagingService) }
  let(:imaging_data) { [instance_double(UnifiedHealthData::ImagingStudy)] }

  before do
    allow(User).to receive(:find).with(user.uuid).and_return(user)
    allow(UnifiedHealthData::ImagingService).to receive(:new).with(user).and_return(imaging_service)
    allow(imaging_service).to receive(:get_imaging_studies).and_return(imaging_data)
    allow(StatsD).to receive(:gauge)
  end

  describe '#perform' do
    context 'when the user exists' do
      it 'fetches imaging data using the configured date range' do
        end_date = Date.current
        days_back = Settings.mhv.uhd.imaging_logging_date_range_days.to_i
        start_date = end_date - days_back.days

        expect(imaging_service).to receive(:get_imaging_studies).with(
          start_date: start_date.strftime('%Y-%m-%d'),
          end_date: end_date.strftime('%Y-%m-%d'),
          site_ids: []
        )

        described_class.new.perform(user.uuid)
      end

      it 'respects custom date range configuration' do
        allow(Settings.mhv.uhd).to receive(:imaging_logging_date_range_days).and_return(7)

        end_date = Date.current
        start_date = end_date - 7.days

        expect(imaging_service).to receive(:get_imaging_studies).with(
          start_date: start_date.strftime('%Y-%m-%d'),
          end_date: end_date.strftime('%Y-%m-%d'),
          site_ids: []
        )

        described_class.new.perform(user.uuid)
      end

      it 'passes site_ids to the imaging service when provided' do
        site_ids = %w[453 200CRNR]

        expect(imaging_service).to receive(:get_imaging_studies).with(
          hash_including(site_ids:)
        )

        described_class.new.perform(user.uuid, site_ids)
      end

      it 'falls back to 180 days when setting is nil' do
        allow(Settings.mhv.uhd).to receive(:imaging_logging_date_range_days).and_return(nil)

        end_date = Date.current
        start_date = end_date - 180.days

        expect(imaging_service).to receive(:get_imaging_studies).with(
          start_date: start_date.strftime('%Y-%m-%d'),
          end_date: end_date.strftime('%Y-%m-%d'),
          site_ids: []
        )

        described_class.new.perform(user.uuid)
      end

      it 'falls back to 180 days when setting is 0' do
        allow(Settings.mhv.uhd).to receive(:imaging_logging_date_range_days).and_return(0)

        end_date = Date.current
        start_date = end_date - 180.days

        expect(imaging_service).to receive(:get_imaging_studies).with(
          start_date: start_date.strftime('%Y-%m-%d'),
          end_date: end_date.strftime('%Y-%m-%d'),
          site_ids: []
        )

        described_class.new.perform(user.uuid)
      end

      it 'falls back to 180 days when setting is negative' do
        allow(Settings.mhv.uhd).to receive(:imaging_logging_date_range_days).and_return(-5)

        end_date = Date.current
        start_date = end_date - 180.days

        expect(imaging_service).to receive(:get_imaging_studies).with(
          start_date: start_date.strftime('%Y-%m-%d'),
          end_date: end_date.strftime('%Y-%m-%d'),
          site_ids: []
        )

        described_class.new.perform(user.uuid)
      end

      it 'logs successful completion' do
        expect(Rails.logger).to receive(:info).with(
          'UHD Imaging Refresh Job completed successfully',
          hash_including(
            records_count: imaging_data.size
          )
        )

        described_class.new.perform(user.uuid)
      end

      it 'returns the count of records fetched' do
        result = described_class.new.perform(user.uuid)
        expect(result).to eq(imaging_data.size)
      end

      it 'sends imaging count metric to StatsD' do
        described_class.new.perform(user.uuid)

        expect(StatsD).to have_received(:gauge).with(
          'unified_health_data.imaging_refresh_job.imaging_count', imaging_data.size
        )
      end
    end

    context 'when the user does not exist' do
      it 'logs an error and returns early' do
        allow(User).to receive(:find).with('nonexistent_uuid').and_return(nil)

        expect(Rails.logger).to receive(:error).with(
          'UHD Imaging Refresh Job: User not found for UUID: nonexistent_uuid'
        )

        described_class.new.perform('nonexistent_uuid')
      end
    end

    context 'when the service raises an error' do
      let(:error_message) { 'Service unavailable' }

      before do
        allow(imaging_service).to receive(:get_imaging_studies).and_raise(StandardError.new(error_message))
      end

      it 'logs the error and re-raises' do
        expect(Rails.logger).to receive(:error).with(
          'UHD Imaging Refresh Job failed',
          hash_including(
            error: error_message
          )
        )

        expect { described_class.new.perform(user.uuid) }.to raise_error(StandardError, error_message)
      end
    end
  end

  describe 'sidekiq options' do
    it 'has a retry count of 0' do
      expect(described_class.get_sidekiq_options['retry']).to eq(0)
    end

    it 'has unique_for of 30 minutes' do
      expect(described_class.get_sidekiq_options['unique_for']).to eq(30.minutes)
    end
  end
end
