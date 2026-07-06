# frozen_string_literal: true

require 'tempfile'

module AccreditedRepresentativePortal
  class UploadForm21aDocumentToGCLAWSJob
    include Sidekiq::Job

    class GclawsDocumentUploadError < StandardError
      attr_reader :status, :response_body

      def initialize(status, response_body = nil)
        @status = status
        @response_body = response_body

        super("GCLAWS Document API returned #{status}")
      end
    end

    class MissingAttachmentFileError < StandardError; end

    FORM_ID = '21a'
    DATADOG_EXHAUSTED_METRIC = 'api.form21a.document_upload.retries_exhausted'
    SLACK_BACKTRACE_LINE_LIMIT = 50
    SLACK_BACKTRACE_CHARACTER_LIMIT = 4000

    # 3 total attempts: 1 initial + 2 retries
    sidekiq_options retry: 2

    sidekiq_retries_exhausted do |job, exception|
      new.send(:record_retries_exhausted, job['args'], exception)
    end

    # @param form21a_attachment_guid [String] GUID of the Form21aAttachment record
    # @param application_id [String] application ID returned from GCLAWS form submission
    # @param document_type [Integer] GCLAWS document type code
    # @param original_file_name [String] Original filename to send to GCLAWS
    # @param content_type [String] MIME type of the file (e.g., "application/pdf")
    def perform(form21a_attachment_guid, application_id, document_type, original_file_name, content_type)
      @form21a_attachment_guid = form21a_attachment_guid
      @application_id = application_id
      @document_type = document_type
      @original_file_name = original_file_name
      @content_type = content_type

      Rails.logger.info(
        "UploadForm21aDocumentToGCLAWSJob: Starting upload for Form21aAttachment guid=#{form21a_attachment_guid} " \
        "to application_id=#{application_id}"
      )

      attachment = find_attachment
      file = retrieve_file(attachment)

      upload_to_gclaws(file)
      delete_attachment(attachment)
    rescue => e
      record_failed_attempt(exception: e)
      raise
    end

    private

    attr_reader :form21a_attachment_guid, :application_id, :document_type, :original_file_name, :content_type

    def find_attachment
      Form21aAttachment.find_by!(guid: form21a_attachment_guid)
    rescue ActiveRecord::RecordNotFound => e
      Rails.logger.error(
        'UploadForm21aDocumentToGCLAWSJob: Form21aAttachment not found; ' \
        "unable to upload document to GCLAWS. guid=#{form21a_attachment_guid} " \
        "application_id=#{application_id}"
      )
      raise e
    end

    def retrieve_file(attachment)
      file = attachment.get_file
      return file if file.present?

      Rails.logger.error(
        'UploadForm21aDocumentToGCLAWSJob: Form21aAttachment returned no file; ' \
        "unable to upload document to GCLAWS. guid=#{form21a_attachment_guid} " \
        "application_id=#{application_id}"
      )

      raise MissingAttachmentFileError, 'Form21aAttachment returned no file for document upload'
    rescue Aws::S3::Errors::ServiceError, Errno::ENOENT => e
      Rails.logger.error(
        "UploadForm21aDocumentToGCLAWSJob: Failed to retrieve file for guid=#{form21a_attachment_guid}.",
        exception: e
      )
      raise
    end

    def upload_to_gclaws(file)
      with_tempfile(file) do |file_path|
        response = connection.post do |req|
          req.headers['x-api-key'] = api_key
          req.body = build_request_body(file_path)
        end

        handle_response(response)
      end
    rescue Faraday::TimeoutError, Faraday::ConnectionFailed => e
      Rails.logger.error(
        'UploadForm21aDocumentToGCLAWSJob: Network error while uploading document ' \
        "guid=#{form21a_attachment_guid} application_id=#{application_id}.",
        exception: e
      )
      raise
    end

    def with_tempfile(file)
      Tempfile.create(['form21a-document-upload', file_extension], binmode: true) do |tempfile|
        tempfile.write(file.read)
        tempfile.rewind

        yield tempfile.path
      end
    end

    def file_extension
      extension = File.extname(safe_original_file_name)

      return extension if extension.present?

      '.bin'
    end

    def build_request_body(file_path)
      {
        'FileDetails' => Faraday::Multipart::FilePart.new(
          file_path,
          content_type,
          safe_original_file_name
        ),
        'FileTypeId' => file_type_id,
        'ApplicationId' => application_id,
        'DocumentTypeId' => document_type,
        'OriginalFileName' => safe_original_file_name
      }
    end

    def safe_original_file_name
      @safe_original_file_name ||= File.basename(original_file_name.to_s)
    end

    def file_type_id
      mapped_file_type = Form21aDocumentUploadConstants.file_type_for(content_type)

      return mapped_file_type if mapped_file_type.present?

      raise ArgumentError, "Unsupported content type for Form21aAttachment upload: #{content_type}"
    end

    def handle_response(response)
      if response.success?
        Rails.logger.info(
          'UploadForm21aDocumentToGCLAWSJob: Successfully uploaded Form21aAttachment ' \
          "guid=#{form21a_attachment_guid} to GCLAWS application_id=#{application_id}"
        )
      else
        Rails.logger.error(
          "UploadForm21aDocumentToGCLAWSJob: GCLAWS API error for guid=#{form21a_attachment_guid}. " \
          "Status: #{response.status}"
        )

        raise GclawsDocumentUploadError.new(response.status, response.body)
      end
    end

    def delete_attachment(attachment)
      attachment.destroy!
      Rails.logger.info(
        'UploadForm21aDocumentToGCLAWSJob: Deleted Form21aAttachment ' \
        "guid=#{form21a_attachment_guid} after successful upload"
      )
    rescue ActiveRecord::RecordNotDestroyed, ActiveRecord::ActiveRecordError => e
      Rails.logger.error(
        "UploadForm21aDocumentToGCLAWSJob: Failed to delete Form21aAttachment guid=#{form21a_attachment_guid}.",
        exception: e
      )
      # Don't re-raise - the upload succeeded, deletion failure shouldn't cause retry
    end

    def record_failed_attempt(exception:)
      classification = failure_classification_for(exception)
      submission = find_or_create_submission

      submission.submission_attempts.create!(
        status: failed_status_for(classification),
        failure_classification: classification,
        last_http_status: http_status_for(exception),
        attempted_at: Time.current,
        metadata: attempt_metadata(exception),
        error_message: exception.message,
        response: response_data_for(exception)
      )
    rescue => e
      Rails.logger.error(
        'UploadForm21aDocumentToGCLAWSJob: Failed to record Form21aDocumentSubmissionAttempt. ' \
        "guid=#{form21a_attachment_guid} application_id=#{application_id}",
        exception: e
      )
    end

    def record_retries_exhausted(job_args, exception)
      assign_job_args(job_args)

      classification = failure_classification_for(exception)
      terminal_status = failed_status_for(classification)
      submission = find_or_create_submission

      # The ticket explicitly asks the exhausted hook to append a final terminal attempt row.
      # This keeps retry failures and terminal exhaustion as separate audit events.
      append_terminal_attempt!(
        submission:,
        classification:,
        terminal_status:,
        exception:
      )

      emit_retries_exhausted_alert(
        classification:,
        terminal_status:,
        exception:
      )
    rescue => e
      log_retries_exhausted_recording_failure(e, exception)
    end

    def assign_job_args(job_args)
      @form21a_attachment_guid,
      @application_id,
      @document_type,
      @original_file_name,
      @content_type = job_args
    end

    def append_terminal_attempt!(submission:, classification:, terminal_status:, exception:)
      submission.submission_attempts.create!(
        status: terminal_status,
        failure_classification: classification,
        last_http_status: http_status_for(exception),
        attempted_at: Time.current,
        metadata: attempt_metadata(exception).merge('terminal' => true),
        error_message: exception.message,
        response: response_data_for(exception)
      )
    end

    def log_retries_exhausted_recording_failure(tracking_error, original_exception)
      Rails.logger.error(
        'UploadForm21aDocumentToGCLAWSJob: Failed to record exhausted upload state. ' \
        "guid=#{form21a_attachment_guid} application_id=#{application_id} " \
        "document_type=#{document_type} content_type=#{content_type}",
        exception: tracking_error
      )

      Rails.logger.error(
        'UploadForm21aDocumentToGCLAWSJob: All retries exhausted. ' \
        "guid=#{form21a_attachment_guid} " \
        "application_id=#{application_id} " \
        "document_type=#{document_type} " \
        "content_type=#{content_type}",
        exception: original_exception
      )
    end

    def find_or_create_submission
      Form21aDocumentSubmission.find_or_create_by!(
        form21a_attachment_guid:
      ) do |submission|
        submission.form_id = FORM_ID
        submission.application_id = application_id
        submission.document_type = document_type
        submission.content_type = content_type
        submission.latest_status = 'pending'
        submission.original_file_name = safe_original_file_name
        submission.identifiers = submission_identifiers
      end
    end

    def submission_identifiers
      {
        'form21a_attachment_guid' => form21a_attachment_guid,
        'application_id' => application_id,
        'document_type' => document_type
      }
    end

    def failure_classification_for(exception)
      status = http_status_for(exception)
      return 'permanent' if status&.between?(400, 499)
      return 'permanent' if permanent_failure_exception?(exception)

      'transient'
    end

    def permanent_failure_exception?(exception)
      exception.is_a?(ArgumentError) || exception.is_a?(ActiveRecord::RecordNotFound)
    end

    def failed_status_for(classification)
      classification == 'permanent' ? 'failed_permanent' : 'failed_transient'
    end

    def http_status_for(exception)
      return exception.status if exception.respond_to?(:status)

      nil
    end

    def attempt_metadata(exception)
      {
        'error_class' => exception.class.name,
        'job_class' => self.class.name,
        'form21a_attachment_guid' => form21a_attachment_guid,
        'application_id' => application_id,
        'document_type' => document_type
      }
    end

    def response_data_for(exception)
      return {} unless exception.is_a?(GclawsDocumentUploadError)

      {
        'status' => exception.status,
        'body' => exception.response_body
      }.compact
    end

    def emit_retries_exhausted_alert(classification:, terminal_status:, exception:)
      emit_retries_exhausted_datadog(
        classification:,
        terminal_status:
      )

      log_retries_exhausted_alert(
        classification:,
        terminal_status:,
        exception:
      )

      notify_retries_exhausted_slack(
        classification:,
        terminal_status:,
        exception:
      )
    end

    def emit_retries_exhausted_datadog(classification:, terminal_status:)
      StatsD.increment(
        DATADOG_EXHAUSTED_METRIC,
        tags: [
          "classification:#{classification}",
          "terminal_status:#{terminal_status}",
          "document_type:#{document_type}",
          "content_type:#{content_type}"
        ]
      )
    end

    def log_retries_exhausted_alert(classification:, terminal_status:, exception:)
      Rails.logger.error(
        'UploadForm21aDocumentToGCLAWSJob: All retries exhausted; terminal upload failure recorded. ' \
        "guid=#{form21a_attachment_guid} " \
        "application_id=#{application_id} " \
        "document_type=#{document_type} " \
        "content_type=#{content_type} " \
        "classification=#{classification} " \
        "terminal_status=#{terminal_status}",
        exception:
      )
    end

    def notify_retries_exhausted_slack(classification:, terminal_status:, exception:)
      VBADocuments::Slack::Messenger
        .new(retries_exhausted_slack_payload(
               classification:,
               terminal_status:,
               exception:
             ))
        .notify!
    rescue => e
      Rails.logger.error(
        'UploadForm21aDocumentToGCLAWSJob: Failed to send Slack alert for exhausted upload. ' \
        "guid=#{form21a_attachment_guid} application_id=#{application_id}",
        exception: e
      )
    end

    def retries_exhausted_slack_payload(classification:, terminal_status:, exception:)
      {
        class: self.class.name,
        alert: '[ALERT] Form 21a document upload retries exhausted: ' \
               "#{exception.class.name} - #{exception.message}",
        details: retries_exhausted_slack_details(
          classification:,
          terminal_status:,
          exception:
        )
      }
    end

    def retries_exhausted_slack_details(classification:, terminal_status:, exception:)
      [
        "guid: #{form21a_attachment_guid}",
        "application_id: #{application_id}",
        "document_type: #{document_type}",
        "content_type: #{content_type}",
        "classification: #{classification}",
        "terminal_status: #{terminal_status}",
        "exception_class: #{exception.class.name}",
        "exception_message: #{exception.message}",
        "backtrace:\n#{formatted_backtrace(exception)}"
      ].join("\n")
    end

    def formatted_backtrace(exception)
      backtrace = Array(exception.backtrace)
                  .first(SLACK_BACKTRACE_LINE_LIMIT)
                  .join("\n")
                  .gsub(Rails.root.to_s, '[APP_ROOT]')

      return backtrace if backtrace.length <= SLACK_BACKTRACE_CHARACTER_LIMIT

      "#{backtrace[0, SLACK_BACKTRACE_CHARACTER_LIMIT]}\n... truncated"
    end

    def connection
      @connection ||= Faraday.new(url: document_upload_url) do |conn|
        conn.options.timeout = 30
        conn.options.open_timeout = 10

        conn.request :multipart
        conn.response :json, content_type: /\bjson$/
        conn.adapter Faraday.default_adapter
      end
    end

    def document_upload_url
      value = Settings.ogc.form21a_service_url.document_upload_url

      return value.to_s if value.present?

      raise ArgumentError, 'Missing OGC Form 21a document upload URL'
    end

    def api_key
      value = Settings.ogc.form21a_service_url.api_key

      return value.to_s if value.present?

      raise ArgumentError, 'Missing OGC Form 21a API key'
    end
  end
end
