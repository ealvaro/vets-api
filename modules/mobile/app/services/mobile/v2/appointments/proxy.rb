# frozen_string_literal: true

require 'lighthouse/facilities/client'

module Mobile
  module V2
    module Appointments
      class Proxy
        VAOS_STATUSES = %w[proposed cancelled booked fulfilled arrived checked-in].freeze

        def initialize(user)
          @user = user
        end

        def get_appointments(start_date:, end_date:, include_pending:, include_claims: false, pagination_params: {})
          statuses = include_pending ? VAOS_STATUSES : VAOS_STATUSES.excluding('proposed')

          include_params = {
            clinics: true,
            facilities: true,
            travel_pay_claims: include_claims,
            # Whether service returns avsPdf is based on: flipper state, whether OH, and start date of appt
            avs: start_date < 1.day.ago.utc
          }

          # VAOS V2 appointments service accepts pagination params but either it formats them incorrectly
          # or the upstream service does not use them.
          response = vaos_v2_appointments_service.get_appointments(start_date, end_date, statuses.join(','),
                                                                   pagination_params, include_params, 'mobile')

          appointments = response[:data]

          unless Flipper.enabled?(:appointments_consolidation, @user)
            filterer = VAOS::V2::AppointmentsPresentationFilter.new(user: @user)
            kept, dropped = appointments.partition { |appt| filterer.user_facing?(appt) }
            log_filtered_appointments(dropped) if dropped.any?
            appointments = kept
          end

          appointments = vaos_v2_to_v0_appointment_adapter.parse(appointments)

          [appointments.sort_by(&:start_date_utc), response[:meta][:failures]]
        end

        private

        def vaos_v2_appointments_service
          VAOS::V2::AppointmentsService.new(@user)
        end

        def vaos_v2_to_v0_appointment_adapter
          Mobile::V0::Adapters::VAOSV2Appointments.new
        end

        # Emits one summary log per request describing the appointments the
        # presentation filter dropped so we can confirm the rollout of
        # :va_online_scheduling_mobile_presentation_filter_update is behaving
        # as expected. Gated on the same flag so we only pay for the log
        # while the feature is enabled.
        def log_filtered_appointments(dropped)
          return unless Flipper.enabled?(:va_online_scheduling_mobile_presentation_filter_update, @user)

          Rails.logger.info(
            'Mobile presentation filter dropped appointments',
            total_dropped: dropped.size,
            cerner_dropped: dropped.count { |a| VAOS::AppointmentsHelper.cerner?(a) },
            missing_created: dropped.count { |a| a[:created].blank? },
            status_counts: dropped.map { |a| a[:status] }.tally
          )
        end
      end
    end
  end
end
