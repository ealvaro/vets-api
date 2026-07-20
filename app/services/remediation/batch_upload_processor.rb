# frozen_string_literal: true

require 'csv'

# rubocop:disable Rails/Output, Rails/Exit -- Intentional stdout and abort for rake task operator console output;
# this service is invoked from a rake task, so aborting on preflight failures is the desired behavior.
module Remediation
  class BatchUploadProcessor
    LOCK_NAME = 'remediation_batch_upload'
    PROGRESS_INTERVAL = 100
    STALE_TIMEOUT = 10.minutes
    CIRCUIT_BREAKER_PAUSE = 60.seconds
    MAX_CIRCUIT_PAUSES = 3

    VALID_FILE_NUMBER = /\A\d{8,9}\z/
    VALID_S3_KEY = %r{\A[\w\-/.]+\z}
    VALID_S3_BUCKET = /\A[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]\z/
    VALID_SUBMISSION_ID = /\A[\w-]+\z/
    VALID_DOC_TYPE_ID = /\A\d+\z/

    LARGE_FILE_THRESHOLD = 500.megabytes
    TEMP_DIR = Rails.root.join('tmp', 'remediation_uploads').to_s

    REQUIRED_CSV_HEADERS = %w[submission_id s3_bucket s3_key file_number document_type_id submission_datetime].freeze

    def initialize(manifest_path:, limit: nil, dry_run: false)
      @manifest_path = manifest_path
      @limit = limit
      @dry_run = dry_run
      @stats = { processed: 0, completed: 0, failed: 0, skipped: 0 }
      @file_number_map = {}
    end

    def run!
      if @dry_run
        run_dry!
        return
      end

      preflight_checks!
      with_exclusive_lock do
        sweep_stale_temp_files!
        ingest_manifest
        recover_stale_rows
        process_items
        print_summary
      end
    end

    def self.print_status
      total = RemediationBatchUploadItem.count
      counts = RemediationBatchUploadItem.group(:status).count
      exhausted = RemediationBatchUploadItem.where(status: 'failed')
                                            .where('retry_count >= ?', RemediationBatchUploadItem::MAX_RETRIES)
                                            .count

      puts '=' * 60
      puts 'BATCH UPLOAD STATUS'
      puts "Total: #{total}"
      counts.each { |status, count| puts "  #{status}: #{count}" }
      puts "  exhausted (max retries): #{exhausted}" if exhausted.positive?
      puts '=' * 60
    end

    private

    def allowed_buckets
      @allowed_buckets ||= begin
        value = Settings.remediation_batch_upload.allowed_s3_buckets
        case value
        when Array then value.map(&:to_s)
        when String then value.split(',').map(&:strip)
        else []
        end
      end
    end

    def preflight_checks!
      abort '[ABORT] allowed_s3_buckets not configured' if allowed_buckets.empty?

      unless Flipper.enabled?(:clamav_scan_file_from_other_location)
        abort '[ABORT] Flipper flag :clamav_scan_file_from_other_location is DISABLED. ' \
              'ClamAV will return {safe: false} for all files. Enable the flag before running.'
      end

      breakers_service = ClaimsEvidenceApi::Configuration.instance.breakers_service
      latest_outage = breakers_service&.latest_outage
      if latest_outage && latest_outage.end_time.nil?
        abort '[ABORT] Claims Evidence API circuit breaker is currently OPEN. ' \
              'Wait for recovery before running batch upload.'
      end
    end

    def with_exclusive_lock(&)
      # with_advisory_lock returns the block's return value (may be nil) on success,
      # or false when the lock was NOT acquired.
      result = RemediationBatchUploadItem.with_advisory_lock(LOCK_NAME, timeout_seconds: 0, &)
      return unless result == false

      abort '[ABORT] Another batch upload instance is already running (advisory lock held).'
    end

    def sweep_stale_temp_files!
      FileUtils.mkdir_p(TEMP_DIR)
      Dir.glob(File.join(TEMP_DIR, 'upload_*')).each do |path|
        if File.mtime(path) < 1.hour.ago
          File.delete(path)
          Rails.logger.info("Swept stale temp file: #{File.basename(path)}")
        end
      end
    end

    def ingest_manifest # rubocop:disable Metrics/MethodLength
      validate_csv_headers!

      row_index = 0
      ingested = 0
      skipped = 0
      errors = []

      CSV.foreach(@manifest_path, headers: true) do |row|
        row_index += 1

        validation_error = validate_row(row, row_index)
        if validation_error
          errors << validation_error
          next
        end

        submission_id = row['submission_id']
        existing = RemediationBatchUploadItem.find_by(submission_id:)
        if existing
          @file_number_map[submission_id] = row['file_number']
          skipped += 1
          next
        end

        RemediationBatchUploadItem.create!(
          submission_id:,
          s3_bucket: row['s3_bucket'],
          s3_key: row['s3_key'],
          document_type_id: row['document_type_id'].to_i,
          submission_datetime: parse_submission_datetime(row['submission_datetime']),
          form_type: row['form_type'].presence,
          subject: row['subject'].presence
        )
        @file_number_map[submission_id] = row['file_number']
        ingested += 1
      end

      puts "Manifest ingested: #{ingested} new, #{skipped} existing, #{errors.size} invalid"
      errors.each { |e| puts "  WARN: #{e}" } if errors.any?
    end

    def validate_row(row, index)
      return "Row #{index}: missing submission_id" unless row['submission_id']&.match?(VALID_SUBMISSION_ID)
      return "Row #{index}: invalid s3_bucket format" unless row['s3_bucket']&.match?(VALID_S3_BUCKET)
      return "Row #{index}: s3_bucket not in allowlist" unless allowed_buckets.include?(row['s3_bucket'])
      return "Row #{index}: invalid s3_key format" unless row['s3_key']&.match?(VALID_S3_KEY)
      return "Row #{index}: s3_key contains traversal sequence" if row['s3_key']&.match?(/\.\.|%2[eE]/)
      return "Row #{index}: invalid file_number format" unless row['file_number']&.match?(VALID_FILE_NUMBER)
      return "Row #{index}: invalid document_type_id" unless row['document_type_id']&.match?(VALID_DOC_TYPE_ID)
      return "Row #{index}: missing submission_datetime" if row['submission_datetime'].blank?
      unless parse_submission_datetime(row['submission_datetime'])
        return "Row #{index}: unparseable submission_datetime"
      end

      nil
    end

    def validate_csv_headers!
      headers = CSV.open(@manifest_path, &:readline)
      missing = REQUIRED_CSV_HEADERS - headers
      return if missing.empty?

      abort "[ABORT] Manifest missing required headers: #{missing.join(', ')}"
    end

    def parse_submission_datetime(value)
      Time.zone.parse(value)
    rescue ArgumentError, TypeError
      nil
    end

    def recover_stale_rows
      count = RemediationBatchUploadItem.stale_in_progress(timeout: STALE_TIMEOUT.ago)
                                        .update_all(status: 'pending', started_at: nil) # rubocop:disable Rails/SkipsModelValidations
      puts "Recovered #{count} stale in-progress rows" if count.positive?
    end

    def process_items
      circuit_pauses = 0

      RemediationBatchUploadItem.actionable.find_each(batch_size: 500) do |item|
        break if @limit && @stats[:processed] >= @limit

        process_single_item(item)
        report_progress if (@stats[:processed] % PROGRESS_INTERVAL).zero?
      rescue Breakers::OutageException
        circuit_pauses += 1
        if circuit_pauses >= MAX_CIRCUIT_PAUSES
          puts "Circuit breaker tripped #{MAX_CIRCUIT_PAUSES} times. Aborting to protect production traffic."
          break
        end
        puts "Circuit breaker open. Pausing #{CIRCUIT_BREAKER_PAUSE.to_i}s..."
        sleep(CIRCUIT_BREAKER_PAUSE)
        retry
      end
    end

    def process_single_item(item)
      if item.claims_evidence_file_uuid.present?
        @stats[:skipped] += 1
        item.update!(status: 'completed') unless item.status == 'completed'
        return
      end

      download_and_upload(item)
      @stats[:processed] += 1
    rescue Breakers::OutageException
      @stats[:processed] += 1
      raise
    rescue => e
      @stats[:processed] += 1
      handle_item_error(item, e)
    end

    def download_and_upload(item)
      temp_file = nil

      item.update!(status: 'downloading', started_at: Time.current)
      temp_file = download_from_s3(item.s3_bucket, item.s3_key)

      item.update!(status: 'uploading')
      response = upload_to_claims_evidence(temp_file.path, item)

      file_uuid = response.body['uuid']
      item.update!(
        status: 'completed',
        completed_at: Time.current,
        claims_evidence_file_uuid: file_uuid
      )
      @stats[:completed] += 1
    ensure
      cleanup_temp_file(temp_file)
    end

    def download_from_s3(bucket, key)
      head = s3_client.head_object(bucket:, key:)
      if head.content_length > LARGE_FILE_THRESHOLD
        Rails.logger.warn("Remediation large file (#{head.content_length} bytes): #{key}")
        StatsD.gauge('remediation.batch_upload.file_size_bytes', head.content_length)
      end

      tempfile = Tempfile.new(['upload_', File.extname(key)], TEMP_DIR)
      tempfile.binmode

      s3_client.get_object(bucket:, key:, response_target: tempfile.path)

      raise "Empty file downloaded: #{key}" if File.size(tempfile.path).zero?

      tempfile
    end

    def s3_client
      @s3_client ||= Aws::S3::Client.new(
        http_open_timeout: 10,
        http_read_timeout: 300
      )
    end

    def upload_to_claims_evidence(file_path, item)
      file_number = @file_number_map[item.submission_id]
      unless file_number
        raise "No file_number in manifest for submission_id=#{item.submission_id}. " \
              'Re-run with the original CSV manifest.'
      end

      service = ClaimsEvidenceApi::Service::Files.new
      folder_id = ClaimsEvidenceApi::FolderIdentifier.generate('VETERAN', 'FILENUMBER', file_number)
      service.folder_identifier = folder_id

      provider_data = {
        contentSource: ClaimsEvidenceApi::CONTENT_SOURCE,
        dateVaReceivedDocument: format_date(item.submission_datetime),
        documentTypeId: item.document_type_id
      }
      provider_data[:subject] = item.subject if item.subject.present?

      service.upload(file_path, provider_data:)
    end

    def format_date(datetime)
      return Time.zone.today.strftime('%Y-%m-%d') unless datetime

      datetime.in_time_zone(ClaimsEvidenceApi::TIMEZONE).strftime('%Y-%m-%d')
    end

    def handle_item_error(item, error)
      sanitized_message = sanitize_error_message(error.message)

      item.update!(
        status: 'failed',
        error_class: error.class.name,
        error_message: sanitized_message,
        retry_count: item.retry_count + 1,
        started_at: nil
      )

      puts "FAILED submission_id=#{item.submission_id} error=#{error.class.name} " \
           "retry=#{item.retry_count}/#{RemediationBatchUploadItem::MAX_RETRIES}"
      @stats[:failed] += 1
    end

    def sanitize_error_message(message)
      message.to_s
             .gsub(/\d{3}[-\s]?\d{2}[-\s]?\d{4}/, '[REDACTED]')
             .gsub(/\d{8,9}/, '[REDACTED]')
             .truncate(500)
    end

    def cleanup_temp_file(temp_file)
      temp_file&.close!
    rescue => e
      Rails.logger.warn("Failed to cleanup temp file: #{e.message}")
    end

    def report_progress
      total = RemediationBatchUploadItem.count
      puts "[PROGRESS] processed=#{@stats[:processed]} completed=#{@stats[:completed]} " \
           "failed=#{@stats[:failed]} skipped=#{@stats[:skipped]} total_in_db=#{total}"
    end

    def print_summary
      puts "\n#{'=' * 60}"
      puts 'BATCH UPLOAD SUMMARY'
      puts "Processed: #{@stats[:processed]}"
      puts "Completed: #{@stats[:completed]}"
      puts "Failed: #{@stats[:failed]}"
      puts "Skipped (already uploaded): #{@stats[:skipped]}"

      failed_ids = RemediationBatchUploadItem.where(status: 'failed').pluck(:submission_id)
      if failed_ids.any?
        puts "\nFailed submission_ids (#{failed_ids.size}):"
        failed_ids.each { |id| puts "  - #{id}" }
      end
      puts '=' * 60
    end

    # --- Dry Run ---

    def run_dry! # rubocop:disable Metrics/MethodLength
      puts "[DRY RUN] Validating manifest: #{@manifest_path}"

      errors = []
      row_count = 0
      missing_s3 = []
      buckets = Set.new

      CSV.foreach(@manifest_path, headers: true) do |row|
        row_count += 1
        validation_error = validate_row(row, row_count)
        errors << validation_error if validation_error
        buckets.add(row['s3_bucket']) if row['s3_bucket']
      end

      puts "[DRY RUN] Manifest contains #{row_count} rows"

      error_count = errors.size
      if error_count.positive?
        puts "[DRY RUN] Validation errors (#{error_count}):"
        errors.first(20).each { |e| puts "  - #{e}" }
        puts "  ... and #{error_count - 20} more" if error_count > 20
      end

      # Check S3 existence (sample first 10)
      check_s3_existence_sample(missing_s3)

      # Check ClamAV Flipper flag
      clamav_ok = Flipper.enabled?(:clamav_scan_file_from_other_location)
      puts "[DRY RUN] ClamAV Flipper flag: #{clamav_ok ? 'ENABLED' : 'DISABLED - uploads will fail!'}"

      # Check Breakers circuit state
      breakers_service = ClaimsEvidenceApi::Configuration.instance.breakers_service
      latest_outage = breakers_service&.latest_outage
      circuit_ok = latest_outage.nil? || latest_outage.end_time.present?
      puts "[DRY RUN] CE API circuit breaker: #{circuit_ok ? 'CLOSED' : 'OPEN - wait for recovery'}"

      # Check S3 bucket allowlist
      invalid_buckets = buckets.to_a - allowed_buckets
      puts "[DRY RUN] S3 buckets NOT in allowlist: #{invalid_buckets.join(', ')}" if invalid_buckets.any?

      puts "\n[DRY RUN] Summary:"
      puts "  Total rows: #{row_count}"
      puts "  Valid rows: #{row_count - error_count}"
      puts "  ClamAV ready: #{clamav_ok}"
      puts "  Circuit breaker clear: #{circuit_ok}"
      puts "  All S3 buckets in allowlist: #{invalid_buckets.empty?}"
    end

    def check_s3_existence_sample(missing)
      sample_rows = []
      CSV.foreach(@manifest_path, headers: true) do |row|
        sample_rows << row
        break if sample_rows.size >= 10
      end

      sample_rows.each do |row|
        key = row['s3_key']
        s3_client.head_object(bucket: row['s3_bucket'], key:)
      rescue Aws::S3::Errors::NotFound, Aws::S3::Errors::NoSuchKey
        missing << key
        puts "[DRY RUN] S3 object missing: #{key}"
      rescue Aws::S3::Errors::Forbidden
        puts "[DRY RUN] S3 access denied: #{key} (check IAM permissions)"
      rescue => e
        puts "[DRY RUN] S3 check error: #{e.class.name} - #{e.message}"
      end

      puts "[DRY RUN] S3 spot check: #{sample_rows.size - missing.size}/#{sample_rows.size} found"
    end
  end
end
# rubocop:enable Rails/Output, Rails/Exit
