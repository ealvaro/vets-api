# frozen_string_literal: true

require 'unified_health_data/imaging_service'

##
# Background job to load imaging study data from the Unified Health Data service
#
module UnifiedHealthData
  class ImagingRefreshJob
    include Sidekiq::Job

    sidekiq_options retry: 0, unique_for: 30.minutes

    def perform(user_uuid, site_ids = [])
      user = find_user(user_uuid)
      return unless user

      start_date, end_date = date_range
      imaging_data = fetch_imaging_data(user, start_date, end_date, site_ids)
      log_success(imaging_data, start_date, end_date)
      StatsD.gauge('unified_health_data.imaging_refresh_job.imaging_count', imaging_data.size)
      imaging_data.size
    rescue => e
      log_error(e)
      raise
    end

    private

    def find_user(user_uuid)
      user = User.find(user_uuid)
      return user if user

      Rails.logger.error("UHD Imaging Refresh Job: User not found for UUID: #{user_uuid}")
      nil
    end

    def date_range
      end_date = Date.current
      days_back = Settings.mhv.uhd.imaging_logging_date_range_days.to_i
      days_back = 180 if days_back <= 0
      start_date = end_date - days_back.days
      [start_date, end_date]
    end

    def fetch_imaging_data(user, start_date, end_date, site_ids)
      imaging_service = UnifiedHealthData::ImagingService.new(user)
      imaging_service.get_imaging_studies(
        start_date: start_date.strftime('%Y-%m-%d'),
        end_date: end_date.strftime('%Y-%m-%d'),
        site_ids:
      )
    end

    def log_success(imaging_data, start_date, end_date)
      Rails.logger.info(
        'UHD Imaging Refresh Job completed successfully',
        records_count: imaging_data.size,
        start_date: start_date.strftime('%Y-%m-%d'),
        end_date: end_date.strftime('%Y-%m-%d')
      )
    end

    def log_error(error)
      Rails.logger.error(
        'UHD Imaging Refresh Job failed',
        error: error.message
      )
    end
  end
end
