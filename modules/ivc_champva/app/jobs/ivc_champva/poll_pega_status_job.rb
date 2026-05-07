# frozen_string_literal: true

require 'sidekiq'
require 'pega_api/client'

# Daily cron job that polls the Pega status API for every IvcChampvaForm that has
# not yet reached a terminal/complete state. It writes the latest Pega status and
# case_id back to the DB record so the frontend can reflect the current stage of the
# veteran's application.
#
# Flow per batch (grouped by form_uuid):
#   1. Query ivc_champva_forms for records where pega_status is NULL or non-terminal
#   2. For each distinct form_uuid, GET the Pega status endpoint with Uuid header = form_uuid
#   3. Match each returned case object to a DB record by case_id
#      (falls back to the first report when case_id is not yet assigned)
#   4. Write pega_status + case_id back to the record via update_columns
module IvcChampva
  class PollPegaStatusJob
    include Sidekiq::Job
    sidekiq_options retry: 3

    FEATURE_TOGGLE = :ivc_champva_poll_pega_status_job
    STATUS_KEYS = ['Determination Type', 'Deternimation Type'].freeze

    # Pega terminal/determination statuses — once a form reaches one of these we stop
    # polling because the application has been fully adjudicated. These match the
    # COMPLETE_STATUSES values in ClaimBuilder and the STATUS_MAP in IvcChampvaFormatter.
    COMPLETE_STATUSES = [
      'eligiblity denied/additional information needed',
      'eligible - issued a card',
      'duplicate application',
      'eligible - reissued a card',
      'additional documentation requested',
      'processed - eligiblity determination unknown',
      'document identification error'
    ].freeze

    def perform
      return unless Flipper.enabled?(FEATURE_TOGGLE)

      form_uuids = pending_form_uuids
      log_start(form_uuids.size)
      return if form_uuids.empty?

      results = process_batches(form_uuids)
      log_complete(results)
    rescue => e
      log_error(e)
    end

    private

    # ──────────────────────────────────────────────
    # Query
    # ──────────────────────────────────────────────

    def pending_forms_scope
      # WHERE NOT IN (...) silently drops NULL rows in SQL, so we explicitly include
      # them — nil means the Pega webhook has never fired for this submission.
      IvcChampvaForm
        .where('pega_status IS NULL OR pega_status NOT IN (?)', COMPLETE_STATUSES)
    end

    def pending_form_uuids
      pending_forms_scope
        .where.not(form_uuid: nil)
        .distinct
        .order(:form_uuid)
        .pluck(:form_uuid)
    end

    def forms_for_uuid(form_uuid)
      pending_forms_scope
        .where(form_uuid:)
        .order(:created_at)
        .to_a
    end

    # ──────────────────────────────────────────────
    # Batch processing
    # ──────────────────────────────────────────────

    def process_batches(form_uuids)
      form_uuids.each_with_object({ updated: 0, skipped: 0, error: 0 }) do |form_uuid, results|
        batch = forms_for_uuid(form_uuid)
        next if batch.empty?

        poll_batch(form_uuid, batch).each { |key, count| results[key] += count }
      end
    end

    def poll_batch(form_uuid, batch)
      reports = pega_api_client.get_status_by_uuid(form_uuid)
      unless valid_reports?(reports)
        log_skip(form_uuid, 'no reports returned from Pega')
        return { updated: 0, skipped: batch.size, error: 0 }
      end

      reports_by_case_id = reports.index_by { |report| report['PEGA Case ID'] }
      fallback_report = reports.first

      outcomes = batch.map { |form| apply_report(form, reports_by_case_id, fallback_report, form_uuid) }

      # Collect actionable skip reasons and emit one summary log per UUID
      # instead of one line per record. "no status change" is logged at debug
      # inside apply_report and intentionally excluded here.
      skip_reasons = outcomes.filter_map { |outcome, reason| reason if outcome == :skipped && reason }
      log_batch_skips(form_uuid, skip_reasons) if skip_reasons.any?

      { updated: outcomes.count { |o, _| o == :updated }, skipped: outcomes.count { |o, _| o == :skipped }, error: 0 }
    rescue IvcChampva::PegaApi::PegaApiError => e
      log_api_error(form_uuid, e)
      { updated: 0, skipped: 0, error: batch.size }
    end

    # ──────────────────────────────────────────────
    # Report application
    # ──────────────────────────────────────────────

    # Finds the report matching this form's case_id (if one exists) and updates
    # the record. Falls back to the first report when case_id is not yet assigned.
    # Returns a 2-tuple [outcome, reason] where outcome is :updated or :skipped.
    # reason is a string for actionable skip cases that get aggregated into a
    # per-UUID summary log, or nil for the high-volume no-change case (logged at debug).
    def apply_report(form, reports_by_case_id, fallback_report, form_uuid)
      report = report_for(form, reports_by_case_id, fallback_report)
      return [:skipped, "no matching report for case_id: #{form.case_id}"] unless report

      status = extract_status(report)
      case_id = report['PEGA Case ID']

      return [:skipped, 'blank status in report'] if status.blank?

      unless needs_update?(form, status, case_id)
        Rails.logger.debug { "IVC Forms PollPegaStatusJob - no status change for case_id: #{case_id}" }
        return [:skipped, nil]
      end

      update_form(form, status, case_id)
      log_update(form_uuid, status, case_id)
      [:updated, nil]
    end

    # If the form already has a case_id, match it to the specific Pega report.
    # Otherwise fall back to the first report so case_id gets assigned.
    def report_for(form, reports_by_case_id, fallback_report)
      form.case_id.present? ? reports_by_case_id[form.case_id] : fallback_report
    end

    def valid_reports?(reports)
      reports.is_a?(Array) && reports.any?
    end

    def extract_status(report)
      STATUS_KEYS.each do |key|
        status = report[key].presence
        return status if status
      end

      nil
    end

    def update_form(form, status, case_id)
      # rubocop:disable Rails/SkipsModelValidations
      form.update_columns(pega_status: status, case_id:, updated_at: Time.current)
      # rubocop:enable Rails/SkipsModelValidations
    end

    def needs_update?(form, status, case_id)
      form.pega_status != status || form.case_id != case_id
    end

    # ──────────────────────────────────────────────
    # Logging
    # ──────────────────────────────────────────────

    def log_start(count)
      Rails.logger.info "IVC Forms PollPegaStatusJob - Found #{count} form UUID(s) to poll"
    end

    # Used for batch-level skips only (e.g., no reports returned from Pega).
    # Per-record skips are aggregated by log_batch_skips instead.
    def log_skip(form_uuid, reason)
      Rails.logger.info "IVC Forms PollPegaStatusJob - Skipping form_uuid: #{form_uuid} - #{reason}"
      :skipped
    end

    def log_batch_skips(form_uuid, reasons)
      summary = reasons.tally.map { |reason, count| "#{reason} (#{count})" }.join(', ')
      Rails.logger.info "IVC Forms PollPegaStatusJob - Skipped records for form_uuid: #{form_uuid} - #{summary}"
    end

    def log_update(form_uuid, status, case_id)
      Rails.logger.info 'IVC Forms PollPegaStatusJob - Updated ' \
                        "form_uuid: #{form_uuid}, status: #{status}, case_id: #{case_id}"
    end

    def log_complete(results)
      Rails.logger.info 'IVC Forms PollPegaStatusJob - Complete - ' \
                        "updated: #{results[:updated]}, skipped: #{results[:skipped]}, errors: #{results[:error]}"
    end

    def log_api_error(form_uuid, error)
      Rails.logger.error 'IVC Forms PollPegaStatusJob - PegaApiError for ' \
                         "form_uuid: #{form_uuid}, error: #{error.message}"
    end

    def log_error(error)
      Rails.logger.error 'IVC Forms PollPegaStatusJob Error',
                         message: error.message,
                         backtrace: error.backtrace&.first(10)
    end

    # ──────────────────────────────────────────────
    # Dependencies
    # ──────────────────────────────────────────────

    def pega_api_client
      @pega_api_client ||= IvcChampva::PegaApi::Client.new
    end
  end
end
