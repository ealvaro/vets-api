# frozen_string_literal: true

# These filters were derived from the web app front end code base. In practice
# this class is a mobile-facing filter today (the web controller only invokes
# it when :appointments_consolidation is off, and that flag is scheduled to
# be removed).
#
# When :va_online_scheduling_mobile_presentation_filter_update is enabled we
# stop filtering appointment requests by :created. VA.gov only allows creating
# appointment requests up to 120 days out, so any request the upstream returns
# is already inside the display window. This unblocks Oracle Health / Cerner
# requests, which never populate :created and were being silently dropped.
#
# When the flag is off we retain the legacy :created-based window check.
module VAOS
  module V2
    class AppointmentsPresentationFilter
      def initialize(user:)
        @user = user
      end

      def user_facing?(appointment)
        return true if valid_appointment?(appointment)

        presentable_requested_appointment?(appointment)
      end

      private

      def presentable_requested_appointment?(appointment)
        return false unless valid_appointment_request?(appointment)
        return false unless appointment[:status].in?(%w[proposed cancelled])
        return true if mobile_presentation_filter_update_enabled?

        created_at = appointment[:created]
        return false unless created_at

        created_at.between?(120.days.ago.beginning_of_day, 1.day.from_now.end_of_day)
      end

      def valid_appointment?(appointment)
        !valid_appointment_request?(appointment) && appointment[:start].present?
      end

      def valid_appointment_request?(appointment)
        appointment[:requested_periods].present?
      end

      def mobile_presentation_filter_update_enabled?
        return @mobile_presentation_filter_update_enabled if defined?(@mobile_presentation_filter_update_enabled)

        @mobile_presentation_filter_update_enabled =
          Flipper.enabled?(:va_online_scheduling_mobile_presentation_filter_update, @user)
      end
    end
  end
end
