# frozen_string_literal: true

require 'logging/helper/data_scrubber'
require 'pagerduty/maintenance_client'
require 'pagerduty/maintenance_windows_uploader'

module PagerDuty
  class CacheGlobalDowntime
    include Sidekiq::Job
    sidekiq_options retry: 1, queue: 'critical'

    def perform
      client = PagerDuty::MaintenanceClient.new
      options = { 'service_ids' => [global_service_id] }
      maintenance_windows = client.get_all(options)
      file_path = 'tmp/maintenance_windows.json'

      File.open(file_path, 'w') do |f|
        f << maintenance_windows.to_json
      end

      PagerDuty::MaintenanceWindowsUploader.upload_file(file_path)
    rescue Common::Exceptions::BackendServiceException, Common::Client::Errors::ClientError => e
      Rails.logger.error(scrub_pii(e.message))
    end

    private

    def scrub_pii(message)
      Logging::Helper::DataScrubber.scrub(message)
    end

    def global_service_id
      Settings.maintenance.services&.to_hash&.dig(:global)
    end
  end
end
