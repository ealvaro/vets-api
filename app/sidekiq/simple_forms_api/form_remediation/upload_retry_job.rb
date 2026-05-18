# frozen_string_literal: true

module SimpleFormsApi
  module FormRemediation
    # Sidekiq job that retries failed S3 uploads for form remediation files.
    #
    # Enqueued by {SimpleFormsApi::FormRemediation::Uploader#store!} when an
    # +Aws::S3::Errors::ServiceError+ occurs during the initial upload attempt.
    #
    # @example Enqueue a retry (typically called from Uploader, not directly)
    # UploadRetryJob.perform_async(temp_file_path, directory, config_class_name)
    # we now pass the temp file path instead of the original file object because the retry job needs to be able
    # access the file even if the original file object
    # has been cleaned up by the caller after the initial upload attempt
    # @see SimpleFormsApi::FormRemediation::Uploader
    class UploadRetryJob
      include Sidekiq::Job

      # Raised when the source file no longer exists on disk.
      # Skips Sidekiq retries since the file will not reappear.
      class FileNoLongerExistsError < StandardError; end

      sidekiq_options retry: 10

      STATSD_KEY_PREFIX = 'api.simple_forms_api.upload_retry_job'

      sidekiq_retries_exhausted do |msg, ex|
        temp_path  = msg['args']&.first.to_s
        s3_dir     = msg['args']&.[](1).to_s
        StatsD.increment("#{STATSD_KEY_PREFIX}.retries_exhausted")

        Rails.logger.error(
          'SimpleFormsApi::FormRemediation::UploadRetryJob retries exhausted - ' \
          'manual remediation required. Temp file preserved for recovery.',
          {
            exception: ex,
            backtrace: ex.backtrace&.first(10)&.join("\n").to_s,
            temp_path:,
            s3_directory: s3_dir
          }
        )
      end

      sidekiq_retry_in do |_count, exception|
        :kill if exception.is_a?(FileNoLongerExistsError)
      end

      # Attempts to upload a file to S3 via the configured uploader.
      #
      # Handles both direct invocation (with objects) and Sidekiq's +perform_async+
      # (where arguments are JSON-serialized into strings/hashes). Each argument is
      # normalized to the expected type before use.
      #
      # @param file [String, Hash, CarrierWave::SanitizedFile] temp file path,
      #   serialised hash, or file object
      # @param directory [String] the S3 target directory
      # @param config [String, Configuration::Base] config class name or instance
      def perform(file, directory, config)
        @file = file.respond_to?(:filename) ? file : CarrierWave::SanitizedFile.new(file)
        @directory = directory
        @config = config.respond_to?(:uploader_class) ? config : config.to_s.constantize.new

        verify_file_exists!(@file)

        uploader = @config.uploader_class.new(directory:, config: @config)

        StatsD.increment("#{STATSD_KEY_PREFIX}.total")

        begin
          uploader.store_for_retry!(@file)
        rescue Aws::S3::Errors::ServiceError
          raise if service_available?(@config.s3_settings.region)

          retry_later
          return
        end

        # Upload succeeded — remove the temp copy inside this job.
        cleanup_temp_file!

        StatsD.increment("#{STATSD_KEY_PREFIX}.success")
      end

      private

      attr_accessor :file, :directory, :config

      # Raises {FileNoLongerExistsError} if the temp file is missing.
      # This kills the Sidekiq job immediately rather than burning retries on
      # a file that will never reappear.
      def verify_file_exists!(sanitized_file)
        path = sanitized_file.respond_to?(:path) ? sanitized_file.path : sanitized_file.to_s
        return if path.blank? || File.exist?(path)

        StatsD.increment("#{STATSD_KEY_PREFIX}.file_missing")
        raise FileNoLongerExistsError,
              "Retry file no longer exists at #{path}. " \
              'The temp copy may have been removed by a previous successful attempt or manual cleanup.'
      end

      # Checks whether the S3 service is reachable in the given region.
      #
      # @param region [String] AWS region (e.g. "us-gov-west-1")
      # @return [Boolean]
      def service_available?(region)
        Aws::S3::Client.new(region:).list_buckets
        true
      rescue Aws::S3::Errors::ServiceError
        false
      end

      # Re-enqueues this job with a delay when S3 is completely unavailable.
      # Uses the current +file.path+ (which already points to the temp copy)
      # so the same file is available when the delayed job runs.
      #
      # @param delay [ActiveSupport::Duration] when to run the retry
      def retry_later(delay: 30.minutes.from_now)
        Rails.logger.info(
          'SimpleFormsApi::FormRemediation::UploadRetryJob - S3 service unavailable, scheduling retry',
          { temp_path: file.path, s3_directory: directory, retry_at: delay }
        )
        self.class.perform_in(delay, file.path, directory, config.class.name)
      end

      # Deletes the temp copy that {Uploader#store!} created for this job.
      # Logs a warning instead of raising if the file is already gone — a
      # concurrent process may have cleaned it up, which is not an error.
      def cleanup_temp_file!
        path = file.respond_to?(:path) ? file.path : file.to_s
        return if path.blank?

        if File.exist?(path)
          FileUtils.rm_f(path)
          Rails.logger.info(
            'SimpleFormsApi::FormRemediation::UploadRetryJob - temp file removed after successful upload',
            { temp_path: path }
          )
        else
          Rails.logger.warn(
            'SimpleFormsApi::FormRemediation::UploadRetryJob - temp file already gone at cleanup; skipping',
            { temp_path: path }
          )
        end
      end
    end
  end
end
