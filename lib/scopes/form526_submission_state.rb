# frozen_string_literal: true

module Scopes
  module Form526SubmissionState
    extend ActiveSupport::Concern

    # rubocop:disable Metrics/BlockLength
    # DOCUMENTATION:
    # https://va.ghe.com/software/va.gov-team/blob/master/products/disability/526ez/engineering_research/526_scopes.md
    included do
      scope :pending_backup, lambda {
        where(submitted_claim_id: nil, backup_submitted_claim_status: nil)
          .where.not(backup_submitted_claim_id: nil)
          .where.missing(:form526_submission_remediations)
          .where(arel_table[:created_at].gt(Form526Submission::MAX_PENDING_TIME.ago))
      }
      scope :in_process, lambda {
        where(submitted_claim_id: nil)
          .where(backup_submitted_claim_id: nil)
          .where(arel_table[:created_at].gt(Form526Submission::MAX_PENDING_TIME.ago))
          .where.not(id: remediated.pluck(:id))
          .where.not(id: with_exhausted_backup_jobs.pluck(:id))
      }

      scope :accepted_to_primary_path, lambda {
        lh = accepted_to_lighthouse_primary_path.pluck(:id)
        evss = accepted_to_evss_primary_path.pluck(:id)
        where(id: lh + evss)
      }
      scope :accepted_to_evss_primary_path, lambda {
        where.not(submitted_claim_id: nil)
             .and(Form526Submission.where(submit_endpoint: nil)
             .or(Form526Submission.where.not(submit_endpoint: 'claims_api')))
      }
      scope :accepted_to_backup_path, lambda {
        where.not(backup_submitted_claim_id: nil)
             .where(
               backup_submitted_claim_status: [
                 backup_submitted_claim_statuses[:accepted],
                 backup_submitted_claim_statuses[:paranoid_success]
               ]
             )
      }
      scope :rejected_from_backup_path, lambda {
        where.not(backup_submitted_claim_id: nil)
             .where(backup_submitted_claim_status: backup_submitted_claim_statuses[:rejected])
      }
      scope :accepted_to_lighthouse_primary_path, lambda {
        left_outer_joins(:form526_job_statuses).where.not(submitted_claim_id: nil)
                                               .where(submit_endpoint: 'claims_api', form526_job_statuses: {
                                                        job_class: 'PollForm526Pdf', status: 'success'
                                                      })
      }

      scope :remediated, lambda {
        # IDs of submissions whose most recent remediation succeeded.
        #
        # Computed from form526_submission_remediations alone via DISTINCT ON (a single
        # scan + sort) rather than a GROUP BY + self-join that also scanned
        # form526_submissions twice. The result is materialized to an id array (like the
        # other scopes here) so the outer query is a plan-stable `id IN (...)` instead of
        # an `id IN (subquery)` semi-join. The semi-join's cost was estimated
        # inconsistently by the planner and intermittently flipped to a plan that timed out.
        latest_remediations = Form526SubmissionRemediation
                              .select('DISTINCT ON (form526_submission_id) form526_submission_id, success')
                              .order(:form526_submission_id, created_at: :desc, id: :desc)
        remediated_ids = Form526SubmissionRemediation
                         .from(latest_remediations, :form526_submission_remediations)
                         .where(success: true)
                         .pluck(:form526_submission_id)
        where(id: remediated_ids)
      }

      scope :with_exhausted_primary_jobs, lambda {
        joins(:form526_job_statuses)
          .where(submitted_claim_id: nil)
          .where(form526_job_statuses: { job_class: 'SubmitForm526AllClaim' })
          .where(form526_job_statuses: { status: Form526JobStatus::FAILURE_STATUSES.values })
      }
      scope :with_exhausted_backup_jobs, lambda {
        joins(:form526_job_statuses)
          .where(backup_submitted_claim_id: nil)
          .where(form526_job_statuses: { job_class: 'BackupSubmission' })
          .where(form526_job_statuses: { status: Form526JobStatus::FAILURE_STATUSES.values })
      }

      # Documentation describing the purpose of 'paranoid success' and 'success by age'
      # https://va.ghe.com/software/va.gov-team/blob/master/products/disability/526ez/engineering_research/paranoid_success_submissions.md
      scope :paranoid_success_type, lambda {
        where.not(backup_submitted_claim_id: nil)
             .where(backup_submitted_claim_status: backup_submitted_claim_statuses[:paranoid_success])
             .where.not(id: success_by_age.pluck(:id))
      }
      scope :success_by_age, lambda {
        where.not(backup_submitted_claim_id: nil)
             .where(backup_submitted_claim_status: backup_submitted_claim_statuses[:paranoid_success])
             .where(arel_table[:created_at].lt(1.year.ago))
      }

      # using .pluck(:id) forces execution of subqueries, preventing PG timeouts
      scope :success_type, lambda {
        ps_ids = accepted_to_primary_path.pluck(:id)
        bs_ids = accepted_to_backup_path.pluck(:id)
        red_ids = remediated.pluck(:id)
        par_ids = paranoid_success.pluck(:id)
        age_ids = success_by_age.pluck(:id)
        where(id: ps_ids + bs_ids + red_ids + par_ids + age_ids)
      }
      scope :incomplete_type, lambda {
        proc_ids = in_process.pluck(:id)
        pend_ids = pending_backup.select(:id)
        where(id: proc_ids + pend_ids)
      }

      scope :failure_type, lambda {
        # Anything that is not success_type or incomplete_type. Each success/incomplete
        # subset is plucked independently and subtracted in Ruby to avoid the PG timeouts
        # that a single chained where.not(id: subquery) caused. See doc for more info.
        #
        # NOTE: accepted_to_primary_path is intentionally NOT subtracted. Every record in
        # it has a non-nil submitted_claim_id, so it can never overlap with the
        # `submitted_claim_id: nil` base set below. Plucking it loaded the entire all-time
        # primary-success set into memory every run for zero effect on the result.
        #
        # NOTE: success_by_age is a strict subset of the paranoid_success enum scope, so it
        # is already removed by the paranoid_success subtraction and does not need its own.
        ids = where(submitted_claim_id: nil).pluck(:id)
        ids -= accepted_to_backup_path.where(submitted_claim_id: nil).pluck(:id)
        ids -= remediated.where(submitted_claim_id: nil).pluck(:id)
        ids -= paranoid_success.where(submitted_claim_id: nil).pluck(:id)
        ids -= incomplete_type.pluck(:id)

        where(id: ids, submitted_claim_id: nil)
      }
    end
    # rubocop:enable Metrics/BlockLength
  end
end
