# frozen_string_literal: true

require 'tempfile'

module AccreditedRepresentativePortal
  class UploadForm21aDocumentToGCLAWSJob
    include Sidekiq::Job

    class GclawsDocumentUploadError < StandardError; end

    # 3 total attempts: 1 initial + 2 retries
    sidekiq_options retry: 2

    sidekiq_retries_exhausted do |job, exception|
      form21a_attachment_guid, application_id, document_type, _original_file_name, content_type = job['args']

      Rails.logger.error(
        'UploadForm21aDocumentToGCLAWSJob: All retries exhausted. ' \
        "guid=#{form21a_attachment_guid} " \
        "application_id=#{application_id} " \
        "document_type=#{document_type} " \
        "content_type=#{content_type}",
        exception:
      )

      # TODO: Add handling for silent GCLAWS document upload failures.
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
      return unless file

      upload_to_gclaws(file)
      delete_attachment(attachment)
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
      attachment.get_file
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

        raise GclawsDocumentUploadError, "GCLAWS Document API returned #{response.status}"
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
