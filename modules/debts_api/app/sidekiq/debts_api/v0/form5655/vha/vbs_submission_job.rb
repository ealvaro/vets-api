# frozen_string_literal: true

require 'debts_api/v0/financial_status_report_service'

module DebtsApi
  class V0::Form5655::VHA::VBSSubmissionJob
    include Sidekiq::Worker
    STATS_KEY = 'api.vbs_submission'

    sidekiq_options retry: 4

    sidekiq_retries_exhausted do |job, ex|
      StatsD.increment("#{STATS_KEY}.failure") # Deprecate this in favor of exhausted naming convention below
      StatsD.increment("#{STATS_KEY}.retries_exhausted")
      submission_id = job['args'][0]

      submission = DebtsApi::V0::Form5655Submission.find(submission_id)
      submission.register_failure("VBS Submission Failed: #{ex.message}")

      Rails.logger.error('V0::Form5655::VHA::VBSSubmissionJob retries exhausted',
                         submission_id:, user_id: submission.user_uuid, exception: ex)
    end

    def perform(submission_id)
      submission = DebtsApi::V0::Form5655Submission.find(submission_id)

      DebtsApi::V0::FinancialStatusReportService.new.submit_to_vbs(submission)
      StatsD.increment("#{STATS_KEY}.success")
    end
  end
end
