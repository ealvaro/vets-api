# frozen_string_literal: true

module AccreditedRepresentativePortal
  class DeleteOldForm21aAttachmentsJob < DeleteAttachmentJob
    ATTACHMENT_CLASSES = [Form21aAttachment.name].freeze
    EXPIRATION_TIME = 30.days

    def uuids_to_keep
      Form21aAttachment
        .where('created_at < ?', self.class::EXPIRATION_TIME.ago)
        .where.not(guid: reapable_attachment_guids)
        .select(:guid)
    end

    private

    def reapable_attachment_guids
      cutoff = EXPIRATION_TIME.ago

      succeeded = Form21aDocumentSubmission
                  .latest_status_succeeded
                  .where('succeeded_at < ?', cutoff)

      abandoned = Form21aDocumentSubmission
                  .latest_status_abandoned
                  .where('last_attempted_at < ?', cutoff)

      succeeded
        .or(abandoned)
        .where.not(form21a_attachment_guid: nil)
        .select(:form21a_attachment_guid)
        .distinct
    end
  end
end
