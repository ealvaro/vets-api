# frozen_string_literal: true

require 'common/exceptions'

module VAOS
  module V2
    module Unified
      ##
      # Orchestrates Wellhive (EPS) draft appointment creation for the unified
      # scheduling slots flow. Two-step contract:
      #
      # 1. Verify the referral hasn't already been used for an existing CCRA or
      #    EPS appointment, via {VAOS::V2::AppointmentsService#referral_appointment_already_exists?}.
      #    If used, surface +422 No new appointment created: referral is already used+
      #    with a +PersonalInformationLog+ entry tagged
      #    +eps_draft_referral_already_used+. If the check itself errored,
      #    surface +502+ with +eps_draft_existing_appointment_check_failed+.
      # 2. Mint a resumable draft via
      #    {Eps::AppointmentService#create_resumable_draft_appointment} (which
      #    also caches the draft id under +(user.uuid, referral_number)+ for
      #    later reuse by {VAOS::V2::Unified::EpsBookingService}).
      #
      # Mirrors the referral-already-used precheck from the legacy EPS
      # draft-creation service (removed with POST /vaos/v2/appointments/draft).
      # Without this, a duplicate booking attempt against an
      # already-used referral would mint a wasted Wellhive draft and surface a
      # generic 4xx at submit time instead of a clean 422 with PII logging.
      #
      # Lives in the +VAOS::V2::Unified+ namespace (rather than +Eps+) so that
      # the cross-source check (VAOS appointments + EPS appointments) doesn't
      # require {Eps::AppointmentService} to take a dependency on
      # {VAOS::V2::AppointmentsService}.
      #
      class EpsDraftService
        STATSD_KEY_PREFIX = 'api.vaos.unified_eps_draft'

        ##
        # @param user [User] the authenticated veteran
        # @param appointments_service [VAOS::V2::AppointmentsService, nil] optional
        #   injection for tests; defaults to a new service built from +user+.
        # @param eps_appointment_service [Eps::AppointmentService, nil] optional
        #   injection for tests; defaults to a new service built from +user+.
        #
        def initialize(user, appointments_service: nil, eps_appointment_service: nil)
          @user = user
          @appointments_service = appointments_service
          @eps_appointment_service = eps_appointment_service
        end

        ##
        # Verify the referral isn't already used and mint a resumable draft.
        #
        # @param referral [#referral_number] CCRA referral object
        # @return [String] the freshly-minted Wellhive draft appointment id
        # @raise [Common::Exceptions::UnprocessableEntity] when the referral has
        #   already been used for an existing CCRA or EPS appointment
        # @raise [Common::Exceptions::BadGateway] when
        #   {VAOS::V2::AppointmentsService#referral_appointment_already_exists?}
        #   reports +error: true+, or when the EPS draft response omits +id+
        # @raise [Eps::ServiceException, Common::Exceptions::BackendServiceException]
        #   when {Eps::AppointmentService#create_resumable_draft_appointment} fails;
        #   those exceptions propagate unchanged from the EPS client layer
        #
        def create_for_referral(referral)
          ensure_referral_unused!(referral.referral_number)

          draft = eps_appointment_service.create_resumable_draft_appointment(
            referral_id: referral.referral_number
          )

          if draft.id.blank?
            raise Common::Exceptions::BadGateway.new(
              detail: 'EPS draft response missing appointment id'
            )
          end

          draft.id
        end

        private

        attr_reader :user

        def ensure_referral_unused!(referral_number)
          check = appointments_service.referral_appointment_already_exists?(referral_number)

          if check[:error]
            log_personal_information_error(
              'eps_draft_existing_appointment_check_failed',
              referral_number,
              "Error checking existing appointments: #{check[:failures]}"
            )
            raise Common::Exceptions::BadGateway.new(
              detail: "Error checking existing appointments: #{check[:failures]}"
            )
          end

          return unless check[:exists]

          log_personal_information_error(
            'eps_draft_referral_already_used',
            referral_number,
            'Referral is already used for an existing appointment'
          )
          raise Common::Exceptions::UnprocessableEntity.new(
            detail: 'No new appointment created: referral is already used'
          )
        end

        def log_personal_information_error(error_class, referral_number, failure_reason)
          # +create+ (not +create!+) so a logging hiccup never breaks the main
          # flow.
          PersonalInformationLog.create(
            error_class:,
            data: {
              referral_number:,
              user_uuid: user&.uuid,
              failure_reason:
            }.compact
          )
          StatsD.increment(
            "#{STATSD_KEY_PREFIX}.#{error_class}",
            tags: ['provider_type:eps']
          )
        end

        def appointments_service
          @appointments_service ||= VAOS::V2::AppointmentsService.new(user)
        end

        def eps_appointment_service
          @eps_appointment_service ||= Eps::AppointmentService.new(user)
        end
      end
    end
  end
end
