# frozen_string_literal: true

module MedicalExpenseReports
  module BenefitsIntake
    # Sidekiq job to backfill the MyVA FormSubmission/FormSubmissionAttempt bookkeeping when the
    # inline write in SubmitClaimJob#update_form_submission_attempt fails. The submit job swallows
    # bookkeeping errors so a successful Lighthouse upload stays terminal (no duplicate uploads);
    # this job restores eventual consistency for the bookkeeping on its own retry schedule.
    #
    # The benefits intake uuid is re-derived from the claim's latest Lighthouse::SubmissionAttempt
    # (created by SubmitClaimJob#lighthouse_submission_polling before every upload) rather than
    # passed as an argument, so a delayed run can never overwrite a newer uuid with a stale one.
    class UpdateFormSubmissionAttemptJob
      include Sidekiq::Job

      # retry for 2d 1h 47m 12s
      # https://github.com/sidekiq/sidekiq/wiki/Error-Handling
      sidekiq_options retry: 16, queue: 'low'

      sidekiq_retries_exhausted do |msg|
        Rails.logger.error(
          'MedicalExpenseReports::BenefitsIntake::UpdateFormSubmissionAttemptJob retries exhausted',
          claim_id: msg['args'].first, error: msg['error_message']
        )
      end

      # The canonical MyVA bookkeeping write, shared with SubmitClaimJob#update_form_submission_attempt.
      # Idempotent: at most one FormSubmission and one FormSubmissionAttempt exist per claim;
      # repeat calls only refresh the benefits intake uuid.
      #
      # @param claim [MedicalExpenseReports::SavedClaim]
      # @param benefits_intake_uuid [String]
      #
      # @return [FormSubmissionAttempt]
      def self.update_form_submission_attempt(claim, benefits_intake_uuid)
        form_submission = claim.form_submissions.order(created_at: :asc).last || FormSubmission.create_with(
          form_type: claim.form_id,
          form_data: claim.to_json,
          saved_claim: claim,
          saved_claim_id: claim.id,
          user_account_id: claim.user_account_id
        ).find_or_create_by!(form_type: claim.form_id, saved_claim_id: claim.id)

        latest_form_submission_attempt = form_submission.latest_attempt
        if latest_form_submission_attempt
          latest_form_submission_attempt.update!(benefits_intake_uuid:)
          latest_form_submission_attempt
        else
          FormSubmissionAttempt.create_with(
            form_submission:
          ).find_or_create_by!(benefits_intake_uuid:)
        end
      end

      # Backfill the FormSubmission/FormSubmissionAttempt records for a claim whose inline
      # bookkeeping write failed. Errors are allowed to raise so Sidekiq retries the backfill;
      # unlike the submit job this carries no risk of re-uploading the document.
      #
      # @param saved_claim_id [Integer] the claim id
      def perform(saved_claim_id)
        claim = MedicalExpenseReports::SavedClaim.find(saved_claim_id)
        benefits_intake_uuid = latest_lighthouse_uuid(claim)

        if benefits_intake_uuid.blank?
          # Without a Lighthouse polling record there is no upload to reflect; nothing to backfill.
          Rails.logger.error(
            'MedicalExpenseReports::BenefitsIntake::UpdateFormSubmissionAttemptJob found no ' \
            'Lighthouse::SubmissionAttempt uuid for claim',
            claim_id: saved_claim_id
          )
          return
        end

        self.class.update_form_submission_attempt(claim, benefits_intake_uuid)
      end

      private

      # The claim's most recent intake uuid, from the Lighthouse polling records created
      # before each upload attempt.
      def latest_lighthouse_uuid(claim)
        Lighthouse::SubmissionAttempt.joins(:submission)
                                     .where(lighthouse_submissions: { saved_claim_id: claim.id })
                                     .where.not(benefits_intake_uuid: nil)
                                     .order(created_at: :asc)
                                     .last
                                     &.benefits_intake_uuid
      end
    end
  end
end
