# frozen_string_literal: true

require 'simple_forms_api/form_remediation/configuration/base'

module SimpleFormsApi
  module FormRemediation
    class Uploader < CarrierWave::Uploader::Base
      include UploaderVirusScan

      # Directory under Dir.tmpdir where temp copies are kept while a retry job
      # is pending. The retry job is responsible for deleting its own copy after
      # a successful upload (or when retries are exhausted).
      RETRY_TEMP_DIR = 'simple_forms_api_upload_retry'

      def initialize(directory:, config:)
        raise 'The S3 directory is missing.' if directory.blank?
        raise 'The configuration is missing.' unless config

        @config = config
        @directory = directory

        super()
        set_storage_options!
      end

      def size_range
        (1.byte)...(150.megabytes)
      end

      # Allowed file types, including those specific to benefits intake
      def extension_allowlist
        %w[bmp csv gif jpeg jpg json pdf png tif tiff txt zip]
      end

      def store_dir
        @directory
      end

      # Attempts to upload +file+ to S3.
      #
      # On success returns the CarrierWave uploader result (truthy).
      #
      # On +Aws::S3::Errors::ServiceError+: copies the file to a dedicated temp
      # location so it survives any downstream cleanup, then enqueues
      # {UploadRetryJob} with the temp path. Returns +false+ so callers can
      # distinguish a deferred upload from a successful one.
      #
      # If the temp copy or enqueue itself fails, delegates to +config.handle_error+
      # so the failure is observable rather than silently dropped.
      #
      # On any other +RuntimeError+: delegates to +config.handle_error+.
      #
      # @param file [CarrierWave::SanitizedFile] the file to upload
      # @return [Object, false] CarrierWave result on success; +false+ when the
      #   upload failed and a retry has been enqueued.
      # @raise [RuntimeError] re-raised via config.handle_error for non-S3 errors
      def store!(file)
        raise 'Invalid file object provided for upload. Skipping.' if file.nil? || !file.respond_to?(:filename)

        super(file)
      rescue Aws::S3::Errors::ServiceError => e
        Rails.logger.error(
          "SimpleFormsApi::FormRemediation::Uploader - upload failed, enqueuing retry for #{file.filename}",
          { error: e.class, message: e.message, directory: @directory }
        )

        begin
          temp_path = copy_to_retry_temp_dir(file)
          UploadRetryJob.perform_async(temp_path, @directory, config.class.name)
        rescue => copy_error
          Rails.logger.error(
            'SimpleFormsApi::FormRemediation::Uploader - failed to prepare temp copy or enqueue retry',
            { error: copy_error.class, message: copy_error.message, directory: @directory }
          )
          config.handle_error('An error occurred while preparing the file for retry upload.', copy_error)
        end

        false
      rescue RuntimeError => e
        config.handle_error('An error occurred while uploading the file.', e)
      end

      # Uploads +file+ to S3 without any retry logic or error rescue.
      #
      # Called by {UploadRetryJob} instead of {#store!} so that
      # +Aws::S3::Errors::ServiceError+ propagates naturally to the job,
      # allowing it to decide between a normal Sidekiq retry and +retry_later+.
      #
      # Using {#store!} from the retry job would cause +ServiceError+ to be
      # swallowed internally, a nested {UploadRetryJob} to be enqueued, and
      # +false+ to be returned — leading the job to incorrectly treat a failed
      # upload as a success and delete the only temp copy.
      #
      # @param file [CarrierWave::SanitizedFile] the file to upload
      # @raise [Aws::S3::Errors::ServiceError] propagated to the caller
      def store_for_retry!(file)
        raise 'Invalid file object provided for upload. Skipping.' if file.nil? || !file.respond_to?(:filename)

        CarrierWave::Uploader::Base.instance_method(:store!).bind_call(self, file)
      end

      def get_s3_link(file_path, filename = nil)
        filename ||= File.basename(file_path)
        s3_obj(file_path).presigned_url(
          :get,
          expires_in: 30.minutes.to_i,
          response_content_disposition: "attachment; filename=\"#{filename}\""
        )
      end

      def get_s3_file(from_path, to_path)
        s3_obj(from_path).get(response_target: to_path)
      rescue Aws::S3::Errors::NoSuchKey
        nil
      rescue => e
        config.handle_error('An error occurred while downloading the file.', e)
      end

      def s3_exists?(file_path)
        s3_obj(file_path).exists?
      rescue Aws::S3::Errors::NotFound, Aws::S3::Errors::NoSuchKey
        false
      rescue => e
        config.handle_error('An error occurred while checking the file.', e)
      end

      private

      attr_reader :config

      # Copies +file+ into a dedicated temp subdirectory so it survives any
      # cleanup of the original archive path that the caller may perform after
      # +store!+ returns.
      #
      # The copy is named with a UUID prefix to avoid collisions when multiple
      # retry jobs are enqueued concurrently for different submissions.
      #
      # @param file [CarrierWave::SanitizedFile]
      # @return [String] absolute path of the temp copy
      def copy_to_retry_temp_dir(file)
        dir = File.join(Dir.tmpdir, RETRY_TEMP_DIR)
        FileUtils.mkdir_p(dir)

        dest = File.join(dir, "#{SecureRandom.uuid}_#{file.filename}")
        FileUtils.cp(file.path, dest)

        Rails.logger.info(
          'SimpleFormsApi::FormRemediation::Uploader - temp copy created for retry',
          { temp_path: dest, original_path: file.path, directory: @directory }
        )

        dest
      end

      def s3_obj(file_path)
        client = Aws::S3::Client.new(region: config.s3_settings.region)
        resource = Aws::S3::Resource.new(client:)
        resource.bucket(config.s3_settings.bucket).object(file_path)
      end

      def set_storage_options!
        settings = config.s3_settings

        self.aws_credentials = { region: settings.region }
        self.aws_acl = 'private'
        self.aws_bucket = settings.bucket
        self.aws_attributes = { server_side_encryption: 'AES256' }
        self.class.storage = :aws
      end
    end
  end
end
