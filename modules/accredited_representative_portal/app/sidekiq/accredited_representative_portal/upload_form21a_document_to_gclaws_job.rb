# frozen_string_literal: true

require 'tempfile'

module AccreditedRepresentativePortal
  # rubocop:disable Metrics/ClassLength
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
    DATADOG_PERMANENT_METRIC = 'api.form21a.document_upload.failed_permanent'
    SLACK_BACKTRACE_LINE_LIMIT = 50
    SLACK_BACKTRACE_CHARACTER_LIMIT = 4000

    SUCCESS_CLASSIFICATION = 'success'
    TRANSIENT_CLASSIFICATION = 'transient'
    PERMANENT_CLASSIFICATION = 'permanent'

    # Keep the permanent 4xx fast-path behind one guard so it can ship disabled
    # if GCLAWS status codes are not reliable enough.
    PERMANENT_FAILURE_FAST_PATH_ENABLED = false

    TRANSIENT_UPLOAD_EXCEPTION_NAMES = [
      'Faraday::TimeoutError',
      'Faraday::ConnectionFailed',
      'Faraday::SSLError',
      'Net::OpenTimeout',
      'Net::ReadTimeout',
      'SocketError',
      'OpenSSL::SSL::SSLError',
      'Errno::ECONNREFUSED',
      'Errno::ECONNRESET',
      'Errno::EHOSTUNREACH',
      'Errno::ETIMEDOUT'
    ].freeze

    AMBIGUOUS_4XX_HTTP_STATUSES = [
      408, # Request Timeout
      409, # Conflict
      425, # Too Early
      429  # Too Many Requests
    ].freeze

    # 3 total attempts: 1 initial + 2 retries
    sidekiq_options retry: 2

    sidekiq_retry_in do |count, _exception|
      [5, 30][count] || 30
    end

    sidekiq_retries_exhausted do |job, exception|
      new.send(:record_retries_exhausted, job['args'], exception)
    end

    # @param form21a_attachment_guid [String] GUID of the Form21aAttachment record
    # @param application_id [String] application ID returned from GCLAWS form submission
    # @param document_type [Integer] GCLAWS document type code
    # @param original_file_name [String] Original filename to send to GCLAWS
    # @param content_type [String] MIME type of the file (e.g., "application/pdf")
    def perform(form21a_attachment_guid, application_id, document_type, original_file_name, content_type)
      assign_job_context(form21a_attachment_guid, application_id, document_type, original_file_name, content_type)
      log_starting_upload

      attachment = find_attachment
      file = retrieve_file(attachment)

      response = upload_to_gclaws(file)
      record_successful_upload(http_status: response.status)
      delete_attachment(attachment)
    rescue => e
      raise unless handle_failed_upload(e)
    end

    private

    attr_reader :form21a_attachment_guid, :application_id, :document_type, :original_file_name, :content_type

    def assign_job_context(form21a_attachment_guid, application_id, document_type, original_file_name, content_type)
      @form21a_attachment_guid = form21a_attachment_guid
      @application_id = application_id
      @document_type = document_type
      @original_file_name = original_file_name
      @content_type = content_type
    end

    def log_starting_upload
      Rails.logger.info(
        "UploadForm21aDocumentToGCLAWSJob: Starting upload for Form21aAttachment guid=#{form21a_attachment_guid} " \
        "to application_id=#{application_id}"
      )
    end

    def handle_failed_upload(exception)
      classification = failure_classification_for(exception)

      return false unless record_failed_attempt(exception:, classification:)

      return false unless classification == PERMANENT_CLASSIFICATION

      emit_permanent_failure_alert(exception:)
      true
    end

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
        response
      end
    rescue => e
      raise unless transient_upload_exception?(e)

      Rails.logger.error(
        'UploadForm21aDocumentToGCLAWSJob: Transport error while uploading document ' \
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
      classification = upload_result_classification_for(response:)

      if classification == SUCCESS_CLASSIFICATION
        Rails.logger.info(
          'UploadForm21aDocumentToGCLAWSJob: Successfully uploaded Form21aAttachment ' \
          "guid=#{form21a_attachment_guid} to GCLAWS application_id=#{application_id}"
        )
      else
        Rails.logger.error(
          "UploadForm21aDocumentToGCLAWSJob: GCLAWS API error for guid=#{form21a_attachment_guid}. " \
          "Status: #{response.status} classification=#{classification}"
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

    def record_successful_upload(http_status:)
      submission = Form21aDocumentSubmission.find_by(form21a_attachment_guid:)

      return unless submission

      persist_successful_upload!(submission, http_status:)
    rescue => e
      log_successful_upload_tracking_failure(e)
    end

    def persist_successful_upload!(submission, http_status:)
      attempted_at = Time.current

      Form21aDocumentSubmission.transaction do
        create_successful_attempt!(submission, http_status:, attempted_at:)
        mark_submission_succeeded!(submission, attempted_at:)
      end
    end

    def create_successful_attempt!(submission, http_status:, attempted_at:)
      submission.submission_attempts.create!(
        status: 'succeeded',
        last_http_status: normalized_http_status(http_status),
        attempted_at:,
        metadata: successful_attempt_metadata
      )
    end

    def mark_submission_succeeded!(submission, attempted_at:)
      submission.update!(
        last_attempted_at: attempted_at,
        next_retry_at: nil,
        succeeded_at: attempted_at
      )
    end

    def log_successful_upload_tracking_failure(error)
      Rails.logger.error(
        'UploadForm21aDocumentToGCLAWSJob: Failed to record successful Form 21a document upload. ' \
        "guid=#{form21a_attachment_guid} " \
        "application_id=#{application_id} " \
        "document_type=#{document_type} " \
        "content_type=#{content_type}",
        exception: error
      )
    end

    def successful_attempt_metadata
      {
        'job_class' => self.class.name,
        'form21a_attachment_guid' => form21a_attachment_guid,
        'application_id' => application_id,
        'document_type' => document_type
      }
    end

    def record_failed_attempt(exception:, classification:)
      attempted_at = Time.current
      submission = find_or_create_submission

      Form21aDocumentSubmission.transaction do
        create_failed_attempt!(
          submission,
          exception:,
          classification:,
          attempted_at:
        )

        submission.update!(last_attempted_at: attempted_at)
      end
    rescue => e
      Rails.logger.error(
        'UploadForm21aDocumentToGCLAWSJob: Failed to record Form21aDocumentSubmissionAttempt. ' \
        "guid=#{form21a_attachment_guid} application_id=#{application_id}",
        exception: e
      )

      false
    end

    def create_failed_attempt!(submission, exception:, classification:, attempted_at:)
      submission.submission_attempts.create!(
        status: failed_status_for(classification),
        failure_classification: classification,
        last_http_status: http_status_for(exception),
        attempted_at:,
        metadata: attempt_metadata(exception),
        error_message: exception.message,
        response: response_data_for(exception)
      )
    end

    def record_retries_exhausted(job_args, exception)
      assign_job_args(job_args)

      classification = failure_classification_for(exception)
      terminal_status = terminal_status_for(classification)
      submission = find_or_create_submission

      # The exhausted hook appends a final terminal attempt row.
      # This is the handoff point for the scheduled re-driver.
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
      attempted_at = Time.current

      submission.submission_attempts.create!(
        status: terminal_status,
        failure_classification: classification,
        last_http_status: http_status_for(exception),
        attempted_at:,
        metadata: attempt_metadata(exception).merge('terminal' => true),
        error_message: exception.message,
        response: response_data_for(exception)
      )

      submission.update!(
        last_attempted_at: attempted_at,
        next_retry_at: next_retry_at_for_terminal_failure(submission, classification)
      )
    end

    def next_retry_at_for_terminal_failure(submission, classification)
      return nil if classification == PERMANENT_CLASSIFICATION

      submission.next_retry_at || Time.current
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

    def upload_result_classification_for(response: nil, exception: nil)
      return PERMANENT_CLASSIFICATION if permanent_failure_exception?(exception)
      return TRANSIENT_CLASSIFICATION if transient_upload_exception?(exception)

      status = http_status_for(exception) || response_status_for(response)

      return SUCCESS_CLASSIFICATION if exception.nil? && status&.between?(200, 299)
      return TRANSIENT_CLASSIFICATION if status&.between?(500, 599)

      if unambiguous_client_error_status?(status) && permanent_failure_fast_path_enabled?
        return PERMANENT_CLASSIFICATION
      end

      TRANSIENT_CLASSIFICATION
    end

    def failure_classification_for(exception)
      classification = upload_result_classification_for(exception:)

      return PERMANENT_CLASSIFICATION if classification == PERMANENT_CLASSIFICATION

      TRANSIENT_CLASSIFICATION
    end

    def permanent_failure_exception?(exception)
      exception.is_a?(ArgumentError) || exception.is_a?(ActiveRecord::RecordNotFound)
    end

    def transient_upload_exception?(exception)
      return false unless exception

      exception.class.ancestors.any? do |ancestor|
        TRANSIENT_UPLOAD_EXCEPTION_NAMES.include?(ancestor.name)
      end
    end

    def unambiguous_client_error_status?(status)
      return false unless status&.between?(400, 499)

      AMBIGUOUS_4XX_HTTP_STATUSES.exclude?(status)
    end

    def permanent_failure_fast_path_enabled?
      PERMANENT_FAILURE_FAST_PATH_ENABLED
    end

    def failed_status_for(classification)
      classification == PERMANENT_CLASSIFICATION ? 'failed_permanent' : 'failed_transient'
    end

    def terminal_status_for(classification)
      failed_status_for(classification)
    end

    def http_status_for(exception)
      return normalized_http_status(exception.status) if exception.respond_to?(:status)

      response = exception.response if exception.respond_to?(:response)

      return normalized_http_status(response.status) if response.respond_to?(:status)

      return normalized_http_status(response[:status] || response['status']) if response.respond_to?(:[])

      nil
    end

    def response_status_for(response)
      return nil unless response.respond_to?(:status)

      normalized_http_status(response.status)
    end

    def normalized_http_status(status)
      Integer(status)
    rescue ArgumentError, TypeError
      nil
    end

    def attempt_metadata(exception)
      {
        'error_class' => exception.class.name,
        'job_class' => self.class.name,
        'form21a_attachment_guid' => form21a_attachment_guid,
        'application_id' => application_id,
        'document_type' => document_type,
        'permanent_fast_path_enabled' => permanent_failure_fast_path_enabled?
      }
    end

    def response_data_for(exception)
      return {} unless exception.is_a?(GclawsDocumentUploadError)

      {
        'status' => exception.status,
        'body' => exception.response_body
      }.compact
    end

    def emit_permanent_failure_alert(exception:)
      StatsD.increment(
        DATADOG_PERMANENT_METRIC,
        tags: [
          "document_type:#{document_type}",
          "content_type:#{content_type}"
        ]
      )

      Rails.logger.error(
        'UploadForm21aDocumentToGCLAWSJob: Permanent upload failure recorded; no in-job retry will be attempted. ' \
        "guid=#{form21a_attachment_guid} " \
        "application_id=#{application_id} " \
        "document_type=#{document_type} " \
        "content_type=#{content_type}",
        exception:
      )
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
  # rubocop:enable Metrics/ClassLength
end
