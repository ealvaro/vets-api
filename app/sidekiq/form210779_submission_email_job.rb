# frozen_string_literal: true

require 'logging/helper/data_scrubber'

class Form210779SubmissionEmailJob
  include Sidekiq::Job

  STATS_KEY = 'api.form210779.email'

  sidekiq_options retry: 14, queue: 'low'

  # Space out retries to ~1 hour for first 9 attempts
  sidekiq_retry_in do |count, _exception|
    rand(3600..3660) if count < 9
  end

  sidekiq_retries_exhausted do |msg, _exception|
    Rails.logger.error(
      'Form210779SubmissionEmailJob retries exhausted',
      saved_claim_id: msg['args'].first
    )
    StatsD.increment("#{STATS_KEY}.retries_exhausted")
  end

  def perform(saved_claim_id)
    return unless feature_enabled?

    claim = load_claim(saved_claim_id)
    template_id = submission_template_id
    return unless template_id

    icn = veteran_icn(claim)
    return unless icn

    send_confirmation_email(claim, icn, template_id)
    track_send_success(claim)
  rescue ActiveRecord::RecordNotFound => e
    handle_claim_not_found(saved_claim_id, e)
  rescue => e
    handle_send_failure(e, saved_claim_id)
    raise
  end

  private

  def feature_enabled?
    return true if Flipper.enabled?(:form_0779_submission_email_notification)

    StatsD.increment("#{STATS_KEY}.skipped_feature_flag")
    false
  end

  def load_claim(saved_claim_id)
    SavedClaim::Form210779.find(saved_claim_id)
  end

  def handle_claim_not_found(saved_claim_id, error)
    StatsD.increment("#{STATS_KEY}.claim_not_found")
    Rails.logger.warn(
      'Form210779SubmissionEmailJob claim not found',
      saved_claim_id:,
      error: error.class.name
    )
    # Don't re-raise = no retries
  end

  def send_confirmation_email(claim, icn, template_id)
    client = notify_client
    return unless client

    client.send_email(
      recipient_identifier: { id_value: icn, id_type: 'ICN' },
      template_id:,
      personalisation: personalisation(claim)
    )
  end

  def track_send_success(claim)
    StatsD.increment("#{STATS_KEY}.sent")
    Rails.logger.info('Form210779SubmissionEmailJob confirmation email sent', saved_claim_id: claim.id,
                                                                              claim_guid: claim.guid)
  end

  def handle_send_failure(error, saved_claim_id)
    StatsD.increment("#{STATS_KEY}.send_failure")
    Rails.logger.error('Form210779SubmissionEmailJob failed to send confirmation email',
                       error: error.class.name,
                       saved_claim_id:)
    Rails.logger.error(scrub_pii(error.message), { saved_claim_id: }.merge({ error: :form210779_submission_email_job }))
  end

  def notify_client
    api_key = Settings.vanotify.services.bio_aquia.api_key.to_s.strip
    if api_key.blank?
      StatsD.increment("#{STATS_KEY}.missing_api_key")
      Rails.logger.error('Form210779SubmissionEmailJob missing vanotify api_key')
      return nil
    end

    @notify_client ||= VaNotify::Service.new(api_key)
  end

  def submission_template_id
    template_id = Settings.vanotify.services.bio_aquia.template_id.form_0779_submission_email
    return template_id if template_id.present?

    StatsD.increment("#{STATS_KEY}.missing_template_id")
    Rails.logger.error('Form210779SubmissionEmailJob missing template_id for form_0779_submission_email')
    nil
  end

  def veteran_icn(claim)
    mpi_response = fetch_mpi_profile(claim)

    if mpi_response&.ok? && mpi_response.profile.present?
      mpi_response.profile.icn
    else
      log_mpi_lookup_failure(claim)
      nil
    end
  rescue => e
    log_mpi_lookup_error(claim, e)
    nil
  end

  def fetch_mpi_profile(claim)
    form_data = claim.parsed_form
    MPI::Service.new.find_profile_by_attributes(
      first_name: form_data.dig('veteranInformation', 'fullName', 'first'),
      last_name: form_data.dig('veteranInformation', 'fullName', 'last'),
      birth_date: form_data.dig('veteranInformation', 'dateOfBirth'),
      ssn: form_data.dig('veteranInformation', 'veteranId', 'ssn')
    )
  end

  def log_mpi_lookup_failure(claim)
    StatsD.increment("#{STATS_KEY}.mpi_lookup_failure")
    Rails.logger.error(
      'Form210779SubmissionEmailJob MPI lookup failed',
      saved_claim_id: claim.id,
      claim_guid: claim.guid
    )
  end

  def log_mpi_lookup_error(claim, error)
    StatsD.increment("#{STATS_KEY}.mpi_lookup_error")
    Rails.logger.error('Form210779SubmissionEmailJob MPI lookup error',
                       error: error.class.name,
                       saved_claim_id: claim.id)
  end

  def personalisation(claim)
    date_str = claim.created_at.in_time_zone('America/New_York').strftime('%B %-d, %Y')
    {
      'first_name' => claim.parsed_form.dig('veteranInformation', 'fullName', 'first'),
      'date_submitted' => date_str,
      'form_name' => '21-0779'
    }.compact
  end

  def scrub_pii(message)
    Logging::Helper::DataScrubber.scrub(message)
  end
end
