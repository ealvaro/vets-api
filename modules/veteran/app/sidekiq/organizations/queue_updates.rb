# frozen_string_literal: true

require 'sidekiq'
require_relative '../concerns/gclaws_xlsx_downloader'

module Organizations
  class QueueUpdates
    include Sidekiq::Job
    include GCLAWSXlsxDownloader

    # Keep retries low — this job runs daily and Sidekiq's exponential backoff with 10 retries
    # could stretch ~21 hours, risking overlap with the next day's scheduled run.
    sidekiq_options retry: 3

    SLICE_SIZE = 30

    def perform(source = 'gclaws')
      with_xlsx_file_content(source:) do |file_content|
        processed_data = Organizations::XlsxFileProcessor.new(file_content).process
        queue_address_updates(processed_data)
      end
    rescue => e
      log_error("Error in file fetching process: #{e.message}")
      raise
    end

    private

    def queue_address_updates(data)
      delay = 0

      Organizations::XlsxFileProcessor::SHEETS_TO_PROCESS.each do |sheet|
        next if data[sheet].blank?

        batch = Sidekiq::Batch.new
        batch.description = "Batching #{sheet} sheet data"

        begin
          batch.jobs do
            rows_to_process(data[sheet]).each_slice(SLICE_SIZE) do |rows|
              json_rows = rows.to_json
              Organizations::Update.perform_in(delay.minutes, json_rows)
              delay += 1
            end
          end
        rescue => e
          log_error("Error queuing address updates: #{e.message}")
        end
      end
    end

    def rows_to_process(rows)
      rows.map do |row|
        org = Veteran::Service::Organization.find_by!(poa: row[:id])
        diff = org.diff(row)
        row.merge(diff.merge({ address_exists: org.location.present? })) if diff.values.any?
      rescue ActiveRecord::RecordNotFound => e
        log_error("Error: Organization not found #{e.message}")
        nil
      end.compact
    end

    def log_error(message)
      Rails.logger.error("QueueUpdates error: #{message}")
    end
  end
end
