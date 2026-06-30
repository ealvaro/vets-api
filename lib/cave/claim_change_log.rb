# frozen_string_literal: true

require 'cave/change_log'

module Cave
  # Orchestrates the CAVE 21-4138 change log for a saved claim:
  #   1. builds the per-field change records (Cave::ChangeLog),
  #   2. persists them on each CaveSubmission (encrypted, retention-bounded),
  #   3. best-effort forwards the corrections to CAVE for accuracy metrics (req: corrections
  #      tracking) — gated behind :cave_change_log_forward_corrections until the CAVE
  #      corrections endpoint is deployed, and
  #   4. returns the Remarks string for the generated 21-4138.
  #
  # Persistence and forwarding are best-effort: a failure is logged but never aborts PDF
  # generation / claim submission.
  class ClaimChangeLog
    STATSD_KEY_PREFIX = 'cave.change_log.forward_corrections'

    def self.remarks_for(saved_claim, form_data)
      new(saved_claim, form_data).remarks
    end

    def initialize(saved_claim, form_data)
      @saved_claim = saved_claim
      @cave_submissions = saved_claim.cave_submissions.to_a
      @change_log = Cave::ChangeLog.new(cave_submissions: @cave_submissions, form_data: form_data || {})
    end

    def remarks
      persist_change_log
      forward_corrections
      @change_log.remarks
    end

    private

    attr_reader :saved_claim, :cave_submissions, :change_log

    def persist_change_log
      cave_submissions.each do |submission|
        records = change_log.records_for(submission)
        submission.update!(change_log: records.map(&:to_h).to_json)
      rescue => e
        Rails.logger.error('[Cave::ClaimChangeLog] failed to persist change log',
                           saved_claim_id: saved_claim.id, cave_submission_id: submission.id, error: e.message)
      end
    end

    def forward_corrections
      return unless Flipper.enabled?(:cave_change_log_forward_corrections)

      cave_submissions.each do |submission|
        records = change_log.records_for(submission)
        next if records.empty? || submission.cave_document_id.blank? ||
                submission.kvpid.blank? || submission.idp_user_id.blank?

        Idp.client.corrections(
          submission.cave_document_id,
          kvpid: submission.kvpid,
          payload: { corrections: records.map(&:to_h) },
          user_id: submission.idp_user_id
        )
        StatsD.increment("#{STATSD_KEY_PREFIX}.success")
      rescue => e
        # Best-effort: never abort claim submission, but the failure MUST be observable
        # (a degraded CAVE corrections endpoint should be alertable, not silent).
        StatsD.increment("#{STATSD_KEY_PREFIX}.failure")
        Rails.logger.warn('[Cave::ClaimChangeLog] failed to forward corrections to CAVE',
                          saved_claim_id: saved_claim.id, cave_submission_id: submission.id, error: e.message)
      end
    end
  end
end
