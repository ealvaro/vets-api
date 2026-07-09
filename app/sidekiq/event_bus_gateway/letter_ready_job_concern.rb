# frozen_string_literal: true

require_relative 'errors'
require_relative 'constants'

module EventBusGateway
  module LetterReadyJobConcern
    extend ActiveSupport::Concern

    private

    def get_bgs_person(participant_id)
      @bgs_person ||= begin
        bgs = BGS::Services.new(external_uid: participant_id, external_key: participant_id)
        person = bgs.people.find_person_by_ptcpnt_id(participant_id)
        raise Errors::BgsPersonNotFoundError, 'Participant ID cannot be found in BGS' if person.nil?

        person
      end
    end

    def get_mpi_profile(participant_id)
      @mpi_profile ||= begin
        person = get_bgs_person(participant_id)
        mpi_response = MPI::Service.new.find_profile_by_attributes(
          first_name: person[:first_nm]&.capitalize,
          last_name: person[:last_nm]&.capitalize,
          birth_date: person[:brthdy_dt]&.strftime('%Y%m%d'),
          ssn: person[:ssn_nbr]
        )

        handle_mpi_response(mpi_response, participant_id)
      end
    end

    def handle_mpi_response(mpi_response, participant_id)
      if mpi_response.nil?
        log_mpi_failure('mpi_nil_response', 'returned nil response', participant_id)
        raise Errors::MpiProfileNotFoundError, 'Failed to fetch MPI profile'
      end

      return mpi_response.profile if mpi_response.ok? && mpi_response.profile.present?

      if mpi_response.server_error?
        log_mpi_failure('mpi_server_error', 'service returned server error', participant_id)
        raise Common::Exceptions::BackendServiceException.new(
          'MPI_502', detail: 'MPI service returned a server error'
        )
      elsif mpi_response.not_found?
        log_mpi_failure('mpi_not_found', 'profile not found', participant_id)
        raise Errors::MpiProfileNotFoundError, 'MPI profile not found for participant'
      else
        log_mpi_failure('mpi_unexpected_state', 'unexpected response state', participant_id)
        raise Errors::MpiProfileNotFoundError, 'Failed to fetch MPI profile'
      end
    end

    def log_mpi_failure(metric_suffix, message, participant_id)
      monitor.track_request(:error, "LetterReadyJob MPI #{message}",
                            "event_bus_gateway.letter_ready.#{metric_suffix}",
                            participant_id:)
    end

    def get_first_name_from_participant_id(participant_id)
      person = get_bgs_person(participant_id)
      person&.dig(:first_nm)&.capitalize
    end

    def get_icn(participant_id)
      get_mpi_profile(participant_id)&.icn
    end

    def record_notification_send_failure(error, job_type)
      error_message = "LetterReady#{job_type}Job #{job_type.downcase} error"
      ::Rails.logger.error(error_message, { message: error.message })

      tags = Constants::DD_TAGS + ["function: #{error_message}"]
      StatsD.increment("#{self.class::STATSD_METRIC_PREFIX}.failure", tags:)
    end

    def user_account(icn)
      UserAccount.find_by(icn:)
    end

    def monitor
      @monitor ||= Logging::Monitor.new('event-bus-gateway-letter-ready')
    end
  end
end
