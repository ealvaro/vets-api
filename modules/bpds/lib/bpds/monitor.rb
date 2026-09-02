# frozen_string_literal: true

require 'logging/monitor'

module BPDS
  # The Monitor class is responsible for tracking and logging various events related to the BPDS service.
  # It inherits from the ZeroSilentFailures::Monitor class and provides methods to track the beginning,
  # success, and failure of submission and JSON retrieval processes.
  class Monitor < Logging::Monitor
    # service name for logging
    SERVICE_NAME = 'BPDS::Service'
    # metric prefix
    STATSD_KEY_PREFIX = 'api.bpds_service'
    # allowed logging params
    ALLOWLIST = %w[
      bpds_uuid
      claim_id
      error
      errors
      lookup_service
      tags
      participant_id_present
      file_number_present
      ssn_present
      icn_present
      edipi_present
      user_is_present
      user_is_nil
      user_class
      user_has_icn
      claim_has_user_account_id
      claim_has_user_account
      form_id
      formatter_class_name
    ].freeze

    def initialize
      super('bpds-service', allowlist: ALLOWLIST)
    end

    # Track service started
    #
    # @param claim_id [Integer] the SavedClaim id
    # @param form_id [String] the SavedClaim form id
    def track_service_begun(claim_id, form_id)
      context = { claim_id:, form_id: }
      track_request(
        :info,
        "#{SERVICE_NAME} begun for saved_claim ##{claim_id}",
        "#{STATSD_KEY_PREFIX}.service_json.begun",
        call_location: caller_locations.first,
        **context
      )
    end

    # Track submission request started
    #
    # @param claim_id [Integer] the SavedClaim id
    # @param form_id [String] the SavedClaim form id
    def track_submit_begun(claim_id, form_id, payload_metrics)
      context = { claim_id:, form_id: }
      track_request(
        :info,
        "#{SERVICE_NAME} submit begun for saved_claim ##{claim_id}",
        "#{STATSD_KEY_PREFIX}.submit_json.begun",
        call_location: caller_locations.first,
        participant_id_present: payload_metrics[:participant_id_present],
        file_number_present: payload_metrics[:file_number_present],
        ssn_present: payload_metrics[:ssn_present],
        icn_present: payload_metrics[:icn_present],
        edipi_present: payload_metrics[:edipi_present],
        **context
      )
    end

    # Track submission successful
    #
    # @param claim_id [Integer] the SavedClaim id
    # @param form_id [String] the SavedClaim form id
    # @param bpds_uuid [String, nil] the UUID returned from BPDS
    def track_submit_success(claim_id, form_id, bpds_uuid = nil)
      context = { claim_id:, form_id:, bpds_uuid: }
      track_request(
        :info,
        "#{SERVICE_NAME} submit succeeded for saved_claim ##{claim_id}",
        "#{STATSD_KEY_PREFIX}.submit_json.success",
        call_location: caller_locations.first,
        **context
      )
    end

    # Track submission request failure
    #
    # @param claim_id [Integer] the SavedClaim id
    # @param form_id [String] the SavedClaim form id
    # @param e [Error] the error which occurred
    def track_submit_failure(claim_id, form_id, e)
      context = {
        claim_id:,
        form_id:,
        error: e&.message,
        errors: e.try(:errors)
      }
      track_request(
        :error,
        "#{SERVICE_NAME} submit failed for saved_claim ##{claim_id}",
        "#{STATSD_KEY_PREFIX}.submit_json.failure",
        call_location: caller_locations.first,
        **context
      )
    end

    # Track a registered formatter that could not be resolved. The job falls back to the raw
    # parsed_form so submission still succeeds, which means this is the only signal that BPDS
    # received unformatted data.
    #
    # @param claim_id [Integer] the SavedClaim id
    # @param form_id [String] the SavedClaim form id
    # @param formatter_class_name [String] the formatter class name that failed to resolve
    # @param e [Error] the error which occurred
    def track_formatter_load_failure(claim_id, form_id, formatter_class_name, e)
      context = {
        claim_id:,
        form_id:,
        formatter_class_name:,
        error: e&.message
      }
      track_request(
        :error,
        "#{SERVICE_NAME} formatter #{formatter_class_name} failed to load for saved_claim ##{claim_id}, " \
        'falling back to unformatted parsed_form',
        "#{STATSD_KEY_PREFIX}.submit_json.formatter_load_failure",
        call_location: caller_locations.first,
        **context
      )
    end

    # Track a formatter that resolved but raised while building the payload. Distinct from
    # #track_formatter_load_failure because the remedy is different: this is a bug inside the
    # formatter, not a class that would not load. NoMethodError is a subclass of NameError, so
    # without a separate metric every nil traversal inside a formatter would be reported as a
    # loading problem and send whoever is on call after the wrong cause.
    #
    # Unlike a load failure this does not fall back: the caller re-raises, so the attempt is
    # recorded as a failure and Sidekiq retries. A class that will not load is not transient and
    # retrying it is noise, but a formatter raising often is, and BPDS is better left without a
    # record than given one built from raw parsed_form under a submitted status.
    #
    # @param claim_id [Integer] the SavedClaim id
    # @param form_id [String] the SavedClaim form id
    # @param formatter_class_name [String] the formatter class name that raised
    # @param e [Error] the error which occurred
    def track_formatter_runtime_error(claim_id, form_id, formatter_class_name, e)
      context = {
        claim_id:,
        form_id:,
        formatter_class_name:,
        error: e&.message
      }
      track_request(
        :error,
        "#{SERVICE_NAME} formatter #{formatter_class_name} raised while building the payload " \
        "for saved_claim ##{claim_id}",
        "#{STATSD_KEY_PREFIX}.submit_json.formatter_runtime_error",
        call_location: caller_locations.first,
        **context
      )
    end

    # Track get_json started
    #
    # @param bpds_uuid [UUID] the uuid generated for a submission
    def track_get_json_begun(bpds_uuid)
      context = { bpds_uuid: }
      track_request(
        :info,
        "#{SERVICE_NAME} get_json begun for bpds_uuid ##{bpds_uuid}",
        "#{STATSD_KEY_PREFIX}.get_json_by_bpds_uuid.begun",
        call_location: caller_locations.first,
        **context
      )
    end

    # Track get_json successful
    #
    # @param bpds_uuid [UUID] the uuid generated for a submission
    def track_get_json_success(bpds_uuid)
      context = { bpds_uuid: }
      track_request(
        :info,
        "#{SERVICE_NAME} get_json succeeded for bpds_uuid ##{bpds_uuid}",
        "#{STATSD_KEY_PREFIX}.get_json_by_bpds_uuid.success",
        call_location: caller_locations.first,
        **context
      )
    end

    # Track get_json failure
    #
    # @param bpds_uuid [UUID] the uuid generated for a submission
    def track_get_json_failure(bpds_uuid, e)
      context = {
        bpds_uuid:,
        error: e&.message,
        errors: e.try(:errors)
      }
      track_request(
        :error,
        "#{SERVICE_NAME} get_json failed for bpds_uuid ##{bpds_uuid}",
        "#{STATSD_KEY_PREFIX}.get_json_by_bpds_uuid.failure",
        call_location: caller_locations.first,
        **context
      )
    end

    # Track user type for user identifier lookup for BPDS
    #
    # @param user_type [String] the user type of the user
    def track_get_user_identifier(user_type)
      context = { tags: ["user_type:#{user_type}"] }
      track_request(
        :info,
        "#{SERVICE_NAME} #{user_type} user identifier lookup for BPDS",
        "#{STATSD_KEY_PREFIX}.get_participant_id",
        call_location: caller_locations.first,
        **context
      )
    end

    # Track result of user identifier lookup for BPDS when checking for participant id, ssn
    #
    # @param lookup_service [String] the service name
    # @param is_pid_present [Boolean] if the participant id is present in the response
    # @param is_ssn_present [Boolean] if the user ssn is present in the response
    def track_get_user_identifier_result(lookup_service, is_pid_present, is_ssn_present)
      context = { lookup_service:, tags: ["pid_present:#{is_pid_present}", "ssn_present:#{is_ssn_present}"] }
      track_request(
        :info,
        "#{SERVICE_NAME} #{lookup_service} service participant_id lookup result: #{is_pid_present}, #{is_ssn_present}",
        "#{STATSD_KEY_PREFIX}.get_participant_id.#{lookup_service}.result",
        call_location: caller_locations.first,
        is_pid_present:,
        is_ssn_present:,
        **context
      )
    end

    # Track result of user identifier lookup for BPDS when checking for file number
    #
    # @param is_file_number_present [Boolean] if the file number is present in the response
    def track_get_user_identifier_file_number_result(is_file_number_present)
      context = { tags: ["file_number_present:#{is_file_number_present}"] }
      track_request(
        :info,
        "#{SERVICE_NAME} BGS service file_number lookup result: #{is_file_number_present}",
        "#{STATSD_KEY_PREFIX}.get_file_number.bgs.result",
        call_location: caller_locations.first,
        **context
      )
    end

    # Tracks and logs the event when a BPDS job is skipped due to a missing user identifier.
    #
    # @param claim_id [Integer, String] The ID of the saved claim for which the BPDS job was skipped.
    # @param form_id [String] the SavedClaim form id
    # @param user [Object] The current user
    def track_skip_bpds_job(claim_id, form_id, user)
      claim = SavedClaim.find_by(id: claim_id) # find_by to not raise an error
      context = {
        claim_id:,
        form_id:,
        user_is_present: user.present?,
        user_is_nil: user.nil?,
        user_class: user.class.name,
        user_has_icn: user&.icn.present?,
        claim_has_user_account_id: claim&.user_account_id.present?,
        claim_has_user_account: claim&.user_account.present?
      }

      extra_message = (' but user is present' if context[:user_is_present])

      track_request(
        :info,
        "#{SERVICE_NAME} No user identifier found#{extra_message}, skipping BPDS job for saved_claim #{claim_id}",
        "#{STATSD_KEY_PREFIX}.job_skipped_missing_identifier",
        call_location: caller_locations.first,
        **context
      )
    end
  end
end
