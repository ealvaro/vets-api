# frozen_string_literal: true

module Mobile
  module V0
    class ReferralsController < ApplicationController
      SUPPORTED_CATEGORIES_OF_CARE = ['primary care'].freeze

      def index
        StatsD.increment('mobile.referrals.index.total')

        response = referral_service.get_vaos_referral_list(
          current_user.icn,
          referral_status_param
        )

        # Filter out expired referrals and unsupported categories of care
        response = filter_expired_referrals(response)
        response = filter_by_category_of_care(response)

        # Add encrypted UUIDs to the referrals for URL usage
        add_referral_uuids(response)

        # Log the referral counts for monitoring purposes
        count = response&.size || 0
        StatsD.gauge('mobile.referrals.index.count', count, tags: ["has_referrals:#{count.positive?}"])

        render json: Mobile::V0::ReferralListSerializer.new(response)
      rescue => e
        StatsD.increment('mobile.referrals.index.failure')
        raise e
      end

      def show
        StatsD.increment('mobile.referrals.show.total')

        decrypted_id = VAOS::ReferralEncryptionService.decrypt(referral_uuid)
        response = referral_service.get_referral(decrypted_id, current_user.icn)
        response.uuid = referral_uuid

        add_appointment_data_to_referral(response)

        render json: Mobile::V0::ReferralDetailSerializer.new(response)
      rescue => e
        StatsD.increment('mobile.referrals.show.failure')
        raise e
      end

      private

      def add_appointment_data_to_referral(referral)
        result = appointments_service.get_active_appointments_for_referral(referral.referral_number)

        eps_appointments = result[:EPS][:data]
        vaos_appointments = result[:VAOS][:data]

        referral.appointments = {
          EPS: {
            data: eps_appointments.map { |appt| { id: appt[:id], status: appt[:status], start: appt[:start] } }
          },
          VAOS: {
            data: vaos_appointments.map { |appt| { id: appt[:id], status: appt[:status], start: appt[:start] } }
          }
        }

        eps_has_active = eps_appointments.any? { |appt| appt[:status] == 'active' }
        vaos_has_active = vaos_appointments.any? { |appt| appt[:status] == 'active' }
        referral.has_appointments = eps_has_active || vaos_has_active
      end

      def appointments_service
        @appointments_service ||= VAOS::V2::AppointmentsService.new(current_user)
      end

      def referral_service
        @referral_service ||= Ccra::ReferralService.new(current_user)
      end

      def referral_uuid
        params.require(:id)
      end

      # CCRA Referral Status Codes:
      # X  - Cancelled
      # BP - EOC Complete: Episode of Care is completed
      # AP - Approved: Referral approved/authorized for care
      # A  - First Appointment Made: Initial appointment scheduled
      # D  - Initial care
      # RJ - Referral Rejected
      # C  - Sent to Care Team
      # AC - Accepted: Referral accepted/authorized for care
      #
      # The referral status parameter for filtering referrals
      def referral_status_param
        params.fetch(:status, "'AP', 'C'")
      end

      def add_referral_uuids(referrals)
        return referrals unless referrals.respond_to?(:each)

        referrals.each do |referral|
          referral.uuid = VAOS::ReferralEncryptionService.encrypt(referral.referral_consult_id)
        end
      end

      def filter_by_category_of_care(referrals)
        referrals.select { |referral| referral.category_of_care.to_s.downcase.in?(SUPPORTED_CATEGORIES_OF_CARE) }
      end

      def filter_expired_referrals(referrals)
        return [] if referrals.nil?
        raise ArgumentError, 'referrals must be an enumerable collection' unless referrals.respond_to?(:each)

        today = Date.current
        referrals.reject { |referral| referral.expiration_date.present? && referral.expiration_date < today }
      end
    end
  end
end
