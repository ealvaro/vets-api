# frozen_string_literal: true

module AccreditedRepresentativePortal
  class PowerOfAttorneyFormSubmissionJob
    class PendingSubmissionError < StandardError; end

    CRITICAL_STEPS = %w[PDF_SUBMISSION POA_UPDATE POA_ACCESS_UPDATE].freeze

    include Sidekiq::Job

    ##
    # This retry duration follows the retry duration used by Lighthouse to
    # accommodate BGS's regular planned maintenance windows of 24 hours.
    #
    # It turns out that Lighthouse's background POA submissions uses the same
    # backoff logic from `Sidekiq` as we do. This means that our status checking
    # will likely pathologically slightly outrace theirs, making us wait until
    # the next poll for an update.
    #
    sidekiq_options retry_for: 48.hours

    attr_reader :response

    sidekiq_retries_exhausted do |job, _ex|
      poa_form_submission_id = job['args'].first
      poa_form_submission = PowerOfAttorneyFormSubmission.find(poa_form_submission_id)
      poa_form_submission.update(status: :failed, status_updated_at: DateTime.current)
      PoaRequestFailureNotifier.new(poa_form_submission.power_of_attorney_request).call

      Monitoring.new.track_duration(
        'ar.poa.submission.failed.duration',
        from: poa_form_submission.created_at,
        to: poa_form_submission.status_updated_at
      )
    end

    def perform(poa_form_submission_id)
      @id = poa_form_submission_id
      @response = service.get_2122_submission(poa_form_submission.service_id)
      poa_form_submission.update(
        status: new_status,
        service_response: response.to_json,
        status_updated_at: DateTime.current,
        error_message: error_data.to_json
      )
      raise PendingSubmissionError, '2122 still pending' if new_status == :enqueue_succeeded

      track_durations
    rescue => e
      handle_errors(e, poa_form_submission)
    end

    private

    def poa_form_submission
      @poa_form_submission ||= PowerOfAttorneyFormSubmission.find(@id)
    end

    def poa_request
      @poa_request ||= poa_form_submission.power_of_attorney_request
    end

    def form_data
      # TODO: Consider adding association between PowerOfAttorneyFormSubmission and PowerOfAttorneyForm
      @form_data ||= poa_request.power_of_attorney_form.parsed_data
    end

    def service
      @service ||= BenefitsClaims::Service.new(veteran_icn)
    end

    def dependent_claimant?
      poa_request.claimant_type == PowerOfAttorneyRequest::ClaimantTypes::DEPENDENT
    end

    def veteran_icn
      if Flipper.enabled?(:form2122_non_veteran_digital_submit) && dependent_claimant?
        veteran_data = {
          first_name: form_data.dig('veteran', 'name', 'first'),
          last_name: form_data.dig('veteran', 'name', 'last'),
          ssn: form_data.dig('veteran', 'ssn'),
          birth_date: form_data.dig('veteran', 'dateOfBirth')
        }
        @veteran_icn ||= ClaimantLookupService.get_icn(
          veteran_data[:first_name],
          veteran_data[:last_name],
          veteran_data[:ssn],
          veteran_data[:birth_date]
        )
      else
        @veteran_icn ||= claimant_icn
      end
    end

    def claimant_icn
      poa_request.claimant.icn
    end

    def handle_errors(e, poa_form_submission)
      poa_form_submission.update(error_message: e.message)
      raise e
    end

    def response_status
      @response_status ||= response.dig('data', 'attributes', 'status')
    end

    def completed_steps
      [].tap do |steps|
        response.dig('data', 'attributes', 'steps').to_a.each do |step|
          steps << step['type'] if step['status'] == 'SUCCESS'
        end
      end
    end

    def failed_steps
      [].tap do |steps|
        response.dig('data', 'attributes', 'steps').to_a.each do |step|
          steps << step['type'] if step['status'] == 'FAILED'
        end
      end
    end

    def track_durations
      Monitoring.new.track_duration(
        'ar.poa.submission.duration',
        from: poa_form_submission.created_at,
        to: poa_form_submission.status_updated_at
      )
      Monitoring.new.track_duration(
        "ar.poa.submission.#{new_status}.duration",
        from: poa_form_submission.created_at,
        to: poa_form_submission.status_updated_at
      )
    end

    # We are using the 'steps' data in the Lighthouse response since the
    # main 'status' attribute does not always accurately reflect the
    # success or failure of the request.
    def new_status
      # If all of the 3 critical steps have succeeded, mark as succeeded
      if Set.new(completed_steps) >= Set.new(CRITICAL_STEPS)
        :succeeded
      # If any of the 3 critical steps have failed, mark as failed
      elsif Set.new(failed_steps).intersect? Set.new(CRITICAL_STEPS)
        PoaRequestFailureNotifier.new(poa_request).call
        :failed
      # Otherwise, continue to query the request
      else
        :enqueue_succeeded
      end
    end

    def error_data
      response.dig('data', 'attributes', 'errors')
    end
  end
end
