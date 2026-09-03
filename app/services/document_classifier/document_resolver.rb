# frozen_string_literal: true

require 'time'

module DocumentClassifier
  # Resolves a completed 526 Veteran upload to one stable Benefits Documents pointer and its document bytes.
  # Raises instead of guessing when the corresponding Documents record is unavailable or ambiguous.
  class DocumentResolver
    class Error < StandardError; end
    class InvalidUpload < Error; end
    class NotReady < Error; end
    class AmbiguousMatch < Error; end
    class DownloadFailed < Error; end

    PAGE_SIZE = 100
    MAX_SEARCH_PAGES = 50
    START_TOLERANCE = 5.minutes
    END_TOLERANCE = 15.minutes

    def initialize(upload:, documents_service: nil)
      @upload = upload
      @documents_service = documents_service || BenefitsDocuments::Service.new(submission.user_account)
    end

    def resolve
      validate_upload!
      matches = recent_filename_matches
      raise NotReady, "No Documents match is available for upload #{@upload.id}" if matches.empty?

      labeled_matches = matches.select { |document| expected_label?(document) }
      matches = labeled_matches if labeled_matches.any?
      unless matches.one?
        raise AmbiguousMatch, "Expected one Documents match for upload #{@upload.id}; found #{matches.length}"
      end

      pointer(matches.first)
    end

    def download(pointer)
      response = @documents_service.participant_documents_download(
        document_uuid: pointer.fetch('document_uuid'),
        participant_id:
      )
      content = response.body
      unless content.is_a?(String) && content.present?
        raise DownloadFailed, "Documents download was empty for upload #{@upload.id}"
      end

      content
    end

    private

    def validate_upload!
      raise InvalidUpload, 'Document upload is not complete' unless @upload.completed?
      raise InvalidUpload, 'Document upload is not a Veteran upload' unless veteran_upload?
      raise InvalidUpload, 'Document upload has no form attachment' if attachment.blank?
      raise InvalidUpload, 'Document upload has no participant ID' if participant_id.blank?
      raise InvalidUpload, 'Document upload has no submitted filename' if submitted_filename.blank?
    end

    def recent_filename_matches
      documents.select do |document|
        normalized_filename(document['originalFileName']) == submitted_filename && uploaded_in_window?(document)
      end
    end

    def documents
      page_number = 1
      results = []
      loop do
        body = @documents_service.participant_documents_search(
          participant_id:,
          page_number:,
          page_size: PAGE_SIZE
        ).body.deep_stringify_keys
        page = body.dig('data', 'documents') || []
        results.concat(page)
        break if last_page?(page_number, page, body.dig('pagination', 'totalPages'))

        page_number += 1
        raise NotReady, 'Documents search exceeded its page limit' if page_number > MAX_SEARCH_PAGES
      end
      results
    end

    def last_page?(page_number, page, total_pages)
      total_pages.present? ? page_number >= total_pages.to_i : page.length < PAGE_SIZE
    end

    def pointer(document)
      document_uuid = document['documentUuid']
      version_uuid = document['currentVersionUuid']
      raise NotReady, 'Matched Documents record has no document UUID' if document_uuid.blank?
      raise NotReady, 'Matched Documents record has no current version UUID' if version_uuid.blank?

      {
        'provider' => 'benefits_documents',
        'document_uuid' => document_uuid,
        'current_version_uuid' => version_uuid,
        'original_filename' => document['originalFileName']
      }
    end

    def uploaded_in_window?(document)
      uploaded_at = Time.iso8601(document['uploadedDateTime'].to_s)
      uploaded_at.between?(search_window.begin, search_window.end)
    rescue ArgumentError
      false
    end

    def expected_label?(document)
      expected_label.present? && document['documentTypeLabel'] == expected_label
    end

    def expected_label
      @expected_label ||= LighthouseDocument::DOCUMENT_TYPES[upload_form_entry&.fetch('attachmentId', nil)]
    end

    def submitted_filename
      @submitted_filename ||= normalized_filename(
        attachment&.converted_filename.presence || upload_form_entry&.fetch('name', nil)
      )
    end

    def normalized_filename(filename)
      filename.to_s.gsub(/[.](?=.*[.])/, '')
    end

    def upload_form_entry
      @upload_form_entry ||= Array(submission.form[Form526Submission::FORM_526_UPLOADS]).find do |entry|
        entry['confirmationCode'] == attachment&.guid
      end
    end

    def search_window
      start_time = @upload.lighthouse_processing_started_at || @upload.created_at
      end_time = @upload.lighthouse_processing_ended_at || Time.current
      (start_time - START_TOLERANCE)..(end_time + END_TOLERANCE)
    end

    def participant_id
      @participant_id ||= submission.auth_headers['va_eauth_pid']
    end

    def veteran_upload?
      @upload.document_type == Lighthouse526DocumentUpload::VETERAN_UPLOAD_DOCUMENT_TYPE
    end

    def attachment = @upload.form_attachment
    def submission = @upload.form526_submission
  end
end
