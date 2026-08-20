# frozen_string_literal: true

require 'bpds/monitor'
require 'bpds/sidekiq/submit_to_bpds_job'

module BPDS
  ##
  # Provides BPDS integration for claim submissions.
  #
  # This concern handles:
  # - User identifier lookup via MPI or BGS
  # - Encrypted payload creation for BPDS submissions
  # - Asynchronous job queueing for BPDS processing
  # - Comprehensive monitoring and logging of the submission process
  #
  # @example Include in a controller
  #   class MyClaimsController < ApplicationController
  #     include BPDS::SubmissionHandler
  #
  #     def create
  #       claim = create_claim(params)
  #       submit_claim_to_bpds(claim.id, claim.form_id, current_user) if claim.save
  #     end
  #   end
  #
  module SubmissionHandler
    extend ActiveSupport::Concern

    ##
    # Submits a claim to BPDS if the feature flag is enabled and user identifiers are available.
    #
    # This method:
    # 1. Checks if BPDS submission is enabled via feature flag
    # 2. Retrieves user identifier (participant_id or file_number)
    # 3. Encrypts the payload for secure transmission
    # 4. Queues the BPDS submission job
    #
    # @param claim_id [Integer] The saved claim id to submit to BPDS
    # @param form_id [String] The saved claim form id
    # @param target_user [User] the user whose identifiers should be sent; default `current_user`
    #
    # @return [Boolean] true if submission was queued, false otherwise
    def submit_claim_to_bpds(claim_id, form_id, target_user = nil)
      return false unless Flipper.enabled?(:bpds_service_enabled)

      bpds_monitor.track_service_begun(claim_id, form_id)

      @user = target_user || current_user
      payload = {
        participant_id: user.try(:participant_id),
        file_number: user.try(:ssn),
        ssn: user.try(:ssn),
        icn: user.try(:icn),
        edipi: user.try(:edipi)
      }.merge(retrieve_user_identifier_for_bpds || {}).compact_blank

      if payload.blank? # no identifiers could be found from any source
        bpds_monitor.track_skip_bpds_job(claim_id, form_id, user)
        return false
      end

      encrypted_payload = KmsEncrypted::Box.new.encrypt(payload.to_json)
      bpds_monitor.track_submit_begun(claim_id, form_id, extract_payload_metrics(payload))
      BPDS::Sidekiq::SubmitToBPDSJob.perform_async(claim_id, encrypted_payload)

      true
    end

    private

    # retrieve the `user` for this instance, assigned when calling `submit_claim_to_bpds`
    # or using the `current_user` of the controller
    # @see SignIn::UserLoader app/services/sign_in/user_loader.rb
    def user
      @user ||= current_user
    end

    ##
    # Retrieves user identifier (participant_id or file_number) for BPDS submission.
    #
    # The lookup strategy depends on user authentication level:
    # - LOA3: Uses MPI service to retrieve participant_id from user profile
    # - LOA1: Uses BGS service to retrieve participant_id or file_number
    # - Unauthenticated: Uses BGS service with form data to retrieve identifiers
    #
    # @return [Hash, nil] Hash with :participant_id or :file_number key, or nil if not found
    #
    def retrieve_user_identifier_for_bpds
      if user&.loa3?
        retrieve_identifier_from_mpi
      elsif user&.loa&.dig(:current).try(:to_i) == LOA::ONE
        bpds_monitor.track_get_user_identifier('loa1')
        retrieve_identifier_from_bgs
      else
        bpds_monitor.track_get_user_identifier('unauthenticated')
        retrieve_identifier_from_bgs
      end
    end

    ##
    # Retrieves participant_id from MPI service for LOA3 users.
    #
    # @return [Hash, nil] Hash with :participant_id key or nil
    #
    def retrieve_identifier_from_mpi
      return nil if user.nil?

      bpds_monitor.track_get_user_identifier('loa3')

      response = MPI::Service.new.find_profile_by_identifier(
        identifier: user&.icn,
        identifier_type: MPI::Constants::ICN
      )

      participant_id = response.profile&.participant_id
      ssn = response.profile&.ssn
      bpds_monitor.track_get_user_identifier_result('mpi', participant_id.present?, ssn.present?)

      { participant_id:, ssn:, edipi: response.profile&.edipi }.compact_blank
    end

    ##
    # Retrieves participant_id or file_number from BGS service.
    #
    # Priority order:
    # 1. participant_id (if present)
    # 2. file_number (if participant_id not present)
    #
    # @return [Hash, nil] Hash with :participant_id or :file_number key, or nil if not found
    #
    def retrieve_identifier_from_bgs
      return nil if user.nil?

      response = BGS::People::Request.new.find_person_by_participant_id(user:)

      participant_id = response.participant_id
      ssn = response.ssn_number
      bpds_monitor.track_get_user_identifier_result('bgs', response.participant_id.present?, ssn.present?)

      file_number = response.file_number
      bpds_monitor.track_get_user_identifier_file_number_result(file_number.present?)

      { participant_id:, file_number:, ssn: }.compact_blank
    end

    ##
    # Returns a hash of the presence/absence for payload sent to BPDS
    #
    # @return [Hash] key:value pairs for the presence/absence of keys in the BPDS payload
    #
    def extract_payload_metrics(payload)
      {
        participant_id_present: payload[:participant_id].present?,
        file_number_present: payload[:file_number].present?,
        ssn_present: payload[:ssn].present?,
        icn_present: payload[:icn].present?,
        edipi_present: payload[:edipi].present?
      }
    end

    ##
    # Returns a memoized BPDS::Monitor instance for tracking submission events.
    #
    # @return [BPDS::Monitor]
    #
    def bpds_monitor
      @bpds_monitor ||= BPDS::Monitor.new
    end
  end
end
