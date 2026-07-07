# frozen_string_literal: true

require 'digital_forms_api/service/submissions'

module DigitalFormsApi
  # Single submit-side seam for routing a form through FDF (BIP Forms API). Builds the BIP
  # metadata envelope, performs the upstream submit, and — on success — records a Submission
  # plus an initial pending SubmissionAttempt so the status poller (A3) has a row to operate on.
  #
  # Integrator controllers call this instead of duplicating the envelope + submit inline. The
  # Flipper gate stays in the caller; this helper is purely the metadata + service + persistence
  # seam.
  #
  # Persistence is best-effort: the upstream submit has already succeeded by the time we write,
  # so a DB failure here is a poller-coverage gap, not a user-facing error. Such failures are
  # logged and StatsD-tracked but never re-raised — the caller still gets the BIP submission
  # hash back exactly as before.
  module SubmissionHelper
    module_function

    # StatsD namespace for this helper's metrics (see .track_record_failure).
    STATSD_KEY_PREFIX = 'api.digital_forms_api.submission_helper'

    # @param claim [SavedClaim] responds to #guid, #claim_form_type, #id
    # @param payload [Hash] the FDF submission payload (e.g. claim.fdf_submission_payload)
    # @param participant_id the veteran/claimant participant id (used for both, per current 686c flow)
    # @param claim_label [String] e.g. "130DPEBNAJRE" — epCode is derived from its leading digits
    # @param user_account [UserAccount, nil] owning account, for My VA scoping (A4)
    # @return [Hash] the BIP `submission` response hash (unchanged from the pre-helper behavior)
    def submit(claim:, payload:, participant_id:, claim_label:, user_account: nil)
      metadata = build_metadata(claim:, participant_id:, claim_label:)

      response = submissions_service.submit(payload, metadata)
      raise response.to_s unless response.success?

      bip_submission = extract_submission(response)
      # Only persist when BIP actually returned a submissionId — it's the poller's durable
      # lookup key and the invariant the Submission model documents. A success response without
      # one is an upstream anomaly, not a row worth writing; surface it instead of persisting nil.
      if bip_submission['submissionId'].present?
        record_submission_and_attempt(claim:, metadata:, bip_submission:, user_account:)
      else
        log_missing_submission_id(metadata)
      end
      bip_submission
    end

    # Pulls the `submission` hash out of the BIP response, tolerant of an unexpected body shape.
    # @return [Hash] the submission hash, or {} when absent/blank
    def extract_submission(response)
      body = response.body
      (body.is_a?(Hash) ? body['submission'].presence : nil) || {}
    end

    # Faithful reproduction of the envelope both integrator controllers built inline.
    # veteranId and claimantId are the same participant today (686c pilot); split them here
    # if a future form needs distinct ids.
    def build_metadata(claim:, participant_id:, claim_label:)
      {
        sourceRequestId: claim.guid,
        formId: claim.claim_form_type,
        veteranId: participant_id,
        claimantId: participant_id,
        epCode: claim_label[/^\d+/],
        claimLabel: claim_label
      }
    end

    # @return [DigitalFormsApi::Service::Submissions] a client for the BIP Forms API submit endpoint
    def submissions_service
      DigitalFormsApi::Service::Submissions.new
    end

    # Creates the Submission + initial pending SubmissionAttempt atomically. Any failure rolls
    # back both rows and is swallowed (logged + StatsD) so it can't break the caller's flow.
    def record_submission_and_attempt(claim:, metadata:, bip_submission:, user_account:)
      ActiveRecord::Base.transaction do
        submission = DigitalFormsApi::Submission.create!(
          form_id: metadata[:formId],
          user_account_id: user_account&.id,
          saved_claim_id: claim.id,
          claim_guid: claim.guid,
          bip_submission_id: bip_submission['submissionId'],
          reference_data: reference_data_for(metadata)
        )

        submission.submission_attempts.create!(
          status: 'pending',
          metadata: metadata.transform_keys(&:to_s),
          response: { 'submission' => bip_submission }
        )
      end
    rescue ActiveRecord::ActiveRecordError => e
      # Narrow to AR errors on purpose: validation / uniqueness / FK failures are the expected,
      # swallowable persistence failures. Programmer errors (NoMethodError, etc.) should NOT be
      # masked here — let them bubble so real defects surface.
      track_record_failure(e, metadata:, bip_submission:)
    end

    # Best-effort persistence failed: log with context and bump the DD metric, then swallow so
    # the caller's already-succeeded submit is unaffected.
    def track_record_failure(error, metadata:, bip_submission:)
      Rails.logger.error(
        'DigitalFormsApi::SubmissionHelper failed to record Submission/SubmissionAttempt',
        bip_submission_id: bip_submission['submissionId'],
        form_id: metadata[:formId],
        error_class: error.class.to_s,
        error: error.message
      )
      StatsD.increment("#{STATSD_KEY_PREFIX}.record_failure", tags: ["form_id:#{metadata[:formId]}"])
    end

    # Upstream returned success but no submissionId, so we skipped persistence. Log it (with the
    # sourceRequestId for correlation) so the poller-coverage gap is visible rather than silent.
    def log_missing_submission_id(metadata)
      Rails.logger.warn(
        'DigitalFormsApi::SubmissionHelper skipped persistence: upstream success without a submissionId',
        form_id: metadata[:formId],
        source_request_id: metadata[:sourceRequestId]
      )
    end

    # Correlation bits that don't have dedicated columns; stored encrypted on the Submission.
    def reference_data_for(metadata)
      {
        'ep_code' => metadata[:epCode],
        'claim_label' => metadata[:claimLabel],
        'source_request_id' => metadata[:sourceRequestId]
      }
    end
  end
end
