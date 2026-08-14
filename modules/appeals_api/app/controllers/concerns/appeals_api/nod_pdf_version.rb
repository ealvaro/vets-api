# frozen_string_literal: true

module AppealsApi
  module NodPdfVersion
    extend ActiveSupport::Concern

    private

    # Selects the 10182 PDF template revision for a submission.
    #
    # `decision_review_nod_june2026_pdf_enabled` globally gates whether the
    # June 2026 form may be used at all — it's the switch for "this template is
    # approved for production use," owned here. Within that gate, the submitted
    # payload picks the revision, so the rendered PDF matches the form the
    # appellant actually filled out even while VA.gov rolls its own flag out to
    # a percentage of users. See
    # AppealsApi::NoticeOfDisagreement#june2026_form? for how the payload
    # identifies a revision.
    def nod_pdf_version(notice_of_disagreement)
      unless Flipper.enabled?(:decision_review_nod_june2026_pdf_enabled)
        log_june2026_form_not_enabled(notice_of_disagreement) if notice_of_disagreement.june2026_form?

        return AppealsApi::NoticeOfDisagreement::FEB2025_PDF_VERSION
      end

      notice_of_disagreement.pdf_version_from_form_data.tap do |pdf_version|
        log_ambiguous_form_revision(notice_of_disagreement, pdf_version) if
          notice_of_disagreement.ambiguous_form_revision?
      end
    end

    # The submitter completed the June 2026 form but the June 2026 template
    # isn't enabled, so their "request a decision as soon as possible" election
    # has no field on the Feb 2025 template and won't reach the Board. Logged
    # as an error because it's silent data loss: nothing else about the
    # submission fails.
    def log_june2026_form_not_enabled(notice_of_disagreement)
      Rails.logger.error(
        'AppealsApi NoticeOfDisagreement: June 2026 payload rendered on the Feb 2025 form',
        'uuid' => notice_of_disagreement.id,
        'api_version' => notice_of_disagreement.api_version,
        'detail' => 'decision_review_nod_june2026_pdf_enabled is disabled; requestDecisionAsap was not rendered'
      )
    end

    def log_ambiguous_form_revision(notice_of_disagreement, pdf_version)
      Rails.logger.warn(
        'AppealsApi NoticeOfDisagreement: submitted payload contradicts the 10182 form revision it resolved to',
        'uuid' => notice_of_disagreement.id,
        'api_version' => notice_of_disagreement.api_version,
        'pdf_version' => pdf_version,
        'contradicted_fields' => notice_of_disagreement.contradicted_form_fields
      )
    end
  end
end
