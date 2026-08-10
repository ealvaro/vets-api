# frozen_string_literal: true

require 'sidekiq'
require 'pega_api/client'

# This job grabs all IVC Forms that are missing a status update from the third-party Pega
# Returns a sends stats to DataDog with the form ids
module IvcChampva
  class MissingFormStatusJob
    include Sidekiq::Job
    sidekiq_options retry: 3

    attr_accessor :additional_context

    def perform
      return unless Settings.ivc_forms.sidekiq.missing_form_status_job.enabled

      batches = if Flipper.enabled?(:champva_ignore_recent_missing_statuses, @current_user)
                  missing_status_cleanup.get_missing_statuses(silent: true, ignore_recent: true)
                else
                  missing_status_cleanup.get_missing_statuses(silent: true, ignore_last_minute: true)
                end

      Rails.logger.info "IVC Forms MissingFormStatusJob - Job started - batch_count: #{batches.count}"

      return unless batches.any?

      # Send the count of forms to DataDog
      StatsD.gauge('ivc_champva.forms_missing_status.count', batches.count)

      form_count = count_forms(batches)

      if form_count > 10
        Rails.logger.info "IVC Forms MissingFormStatusJob - Too many forms to log details (#{form_count} forms)"
      end

      current_time = Time.now.utc
      process_batches(batches, current_time, form_count)

      Rails.logger.info 'IVC Forms MissingFormStatusJob - Job completed successfully'
    rescue => e
      Rails.logger.error "IVC Forms MissingFormStatusJob Error: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
    end

    # Helper function to process batches of forms
    def process_batches(batches, current_time, form_count)
      batches.each_value do |batch|
        form = batch[0] # get a representative form from this submission batch
        elapsed_days = (current_time - form.created_at).to_i / 1.day

        log_batch_processing(form, batch, elapsed_days)

        # Check reporting API to see if this missing status is a false positive
        next if num_docs_match_reports?(batch)

        send_failure_email_if_threshold_exceeded(form, elapsed_days)
        publish_missing_status_metric(form)
        log_verbose_missing_status(form, elapsed_days, form_count)
      end
    end

    def log_batch_processing(form, batch, elapsed_days)
      file_names_str = batch.count <= 10 ? batch.map(&:file_name).to_s : 'Too many files to log'
      Rails.logger.info 'IVC Forms MissingFormStatusJob processing batch - ' \
                        "form_uuid: #{form.form_uuid}, form_number: #{form.form_number}, " \
                        "elapsed_days: #{elapsed_days}, local_doc_count: #{batch.count}, " \
                        "email_sent: #{form.email_sent}, file_names: #{file_names_str}"
    end

    def send_failure_email_if_threshold_exceeded(form, elapsed_days)
      threshold = Settings.vanotify.services.ivc_champva.failure_email_threshold_days.to_i || 7
      return unless elapsed_days >= threshold && !form.email_sent

      template_id = "#{form[:form_number]}-FAILURE"
      additional_context = { form_id: form[:form_number], form_uuid: form[:form_uuid] }

      send_failure_email(form, template_id, additional_context)

      Rails.logger.info 'IVC Forms MissingFormStatusJob - Failure ZSF email sent to user - ' \
                        "form_uuid: #{form.form_uuid}, form_number: #{form.form_number}, " \
                        "elapsed_days: #{elapsed_days}"
    end

    def publish_missing_status_metric(form)
      key = "#{form.form_uuid}_#{form.s3_status}_#{form.created_at.strftime('%Y%m%d_%H%M%S')}"
      StatsD.increment('ivc_champva.form_missing_status', tags: ["key:#{key}"])
    end

    def log_verbose_missing_status(form, elapsed_days, form_count)
      return unless form_count <= 10

      Rails.logger.info "IVC Forms MissingFormStatusJob - Missing status for Form #{form.form_uuid} " \
                        "- Elapsed days: #{elapsed_days} - File name: #{form.file_name} " \
                        "- S3 status: #{form.s3_status} - Created at: #{form.created_at.strftime('%Y%m%d_%H%M%S')}"
    end

    def count_forms(batches)
      batches.values.sum(&:count)
    end

    def construct_email_payload(form, template_id)
      { email: form.email,
        first_name: form.first_name,
        last_name: form.last_name,
        form_number: form.form_number,
        file_count: nil,
        pega_status: form.pega_status,
        date_submitted: form.created_at.strftime('%B %d, %Y'),
        template_id:,
        form_uuid: form.form_uuid }
    end

    # Sends an email to user notifying them of their submission's failure
    #
    # @param form [IvcChampvaForm] form object in question
    # @param template_id [string] key for template to use in `IvcChampva::Email::EMAIL_TEMPLATE_MAP`
    # @param additional_context [hash] contains properties form_id and form_uuid
    #   (e.g.: {form_id: '10-10d', form_uuid: '12345678-1234-5678-1234-567812345678'})
    def send_failure_email(form, template_id, additional_context)
      form_data = construct_email_payload(form, template_id).merge(callback_hash(additional_context))

      ActiveRecord::Base.transaction do
        if IvcChampva::Email.new(form_data).send_email
          IvcChampvaForm.where(form_uuid: form[:form_uuid]).update_all(email_sent: true) # rubocop:disable Rails/SkipsModelValidations
          monitor.track_missing_status_email_sent(form[:form_number])
        else
          monitor.log_silent_failure(additional_context)
          raise ActiveRecord::Rollback, 'Pega Status Update/Action Required Email send failure'
        end
      end
    end

    # return the hash fields used for vanotify callback
    def callback_hash(additional_context)
      {
        callback_klass: 'IvcChampva::ZsfEmailNotificationCallback',
        callback_metadata: {
          statsd_tags: { service: 'veteran-ivc-champva-forms', function: 'IVC CHAMPVA send_failure_email' },
          additional_context:
        }
      }
    end

    ##
    # Checks PEGA reporting API to see if this batch's form_uuid is associated with an
    # identical number of records on PEGA's side - If so, sets these records to
    # "Manually Processed" and returns true. If the numbers differ, returns false.
    #
    # @param batch [Array<IvcChampvaForm>] An array of IVC CHAMPVA form objects with common form_uuid
    #   (representing a single user's submission, including all supporting documents)
    # @return [boolean] true if PEGA's reporting API has same number of documents for this batch; false otherwise
    def num_docs_match_reports?(batch)
      return false if batch.empty?

      form = batch.first
      matching_reports = pega_api_client.record_has_matching_report(form)
      pega_processable_batch = filter_pega_processable_files(batch)

      local_count = pega_processable_batch.count
      pega_count = matching_reports.is_a?(Array) ? matching_reports.count : 0
      counts_match = local_count == pega_count

      log_pega_report_comparison(form, batch, local_count, pega_count, counts_match)
      reconcile_batch_if_counts_match(form, batch, local_count, pega_count, counts_match)
    rescue IvcChampva::PegaApi::PegaApiError => e
      Rails.logger.error 'IVC Forms MissingFormStatusJob - PegaApiError during report check - ' \
                         "form_uuid: #{batch.first&.form_uuid}, error: #{e.message}"
      false
    end

    def log_pega_report_comparison(form, batch, local_count, pega_count, counts_match)
      file_names_str = batch.count <= 10 ? batch.map(&:file_name).to_s : 'Too many files to log'
      Rails.logger.info 'IVC Forms MissingFormStatusJob - Pega report comparison - ' \
                        "form_uuid: #{form.form_uuid}, local_pega_processable_count: #{local_count}, " \
                        "pega_report_count: #{pega_count}, counts_match: #{counts_match}, " \
                        "file_names: #{file_names_str}"
    end

    def reconcile_batch_if_counts_match(form, batch, local_count, pega_count, counts_match)
      return false unless counts_match && pega_count.positive?

      missing_status_cleanup.manually_process_batch(batch)
      Rails.logger.info 'IVC Forms MissingFormStatusJob - Batch reconciled via Pega API - ' \
                        "form_uuid: #{form.form_uuid}, doc_count: #{local_count}, new_status: Manually Processed"
      true
    end

    def monitor
      @monitor ||= IvcChampva::Monitor.new
    end

    def missing_status_cleanup
      @missing_status_cleanup ||= IvcChampva::ProdSupportUtilities::MissingStatusCleanup.new
    end

    def pega_api_client
      @pega_api_client ||= IvcChampva::PegaApi::Client.new
    end

    private

    ##
    # Filters batch to only include files that were actually uploaded to S3 for Pega to process.
    # Records with a successful s3_status (200) represent files sent to Pega.
    # Records without s3_status are original files preserved for email counting after combining.
    # VES JSON files are excluded as a safety net for historical records.
    #
    # @param batch [Array<IvcChampvaForm>] An array of IVC CHAMPVA form objects
    # @return [Array<IvcChampvaForm>] Filtered array of Pega-processable files
    def filter_pega_processable_files(batch)
      batch.select { |record| pega_processable?(record) }
    end

    ##
    # Determines if a record represents a file that was sent to Pega
    #
    # @param record [IvcChampvaForm] The form record to check
    # @return [Boolean] true if the file was uploaded to S3 for Pega processing
    def pega_processable?(record)
      return false if record.s3_status.blank?
      return false if IvcChampva::FileNaming.ves_json?(record.file_name)

      record.s3_status.include?('200')
    end
  end
end
