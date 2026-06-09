# frozen_string_literal: true

module Mobile
  module V0
    class ReferralDetailSerializer
      include JSONAPI::Serializer

      # Categories of care that support online scheduling. Until the CCRA API can tell us per-referral
      # whether online scheduling is supported, we approximate it from the category of care.
      ONLINE_SCHEDULE_CATEGORIES = ['primary care'].freeze

      set_id :uuid
      set_type :referrals

      attribute :category_of_care
      attribute :expiration_date
      attribute :referral_number
      attribute :referral_consult_id
      attribute :uuid
      attribute :has_appointments
      attribute :appointments
      attribute :referral_date
      attribute :station_id
      attribute :online_schedule do |referral|
        ONLINE_SCHEDULE_CATEGORIES.include?(referral.category_of_care.to_s.downcase)
      end

      attribute :provider do |referral|
        provider_info = {
          name: referral.provider_name,
          facility_name: referral.treating_facility_name,
          npi: referral.provider_npi,
          phone: referral.treating_facility_phone,
          specialty: referral.provider_specialty
        }

        address = referral.treating_facility_address
        if address.present? && address.values.any?(&:present?)
          provider_info[:address] = {
            street1: address[:street1],
            city: address[:city],
            state: address[:state],
            zip: address[:zip]
          }
        end

        provider_info.transform_keys { |key| key.to_s.camelize(:lower).to_sym }
      end

      attribute :referring_facility do |referral|
        next if referral.referring_facility_name.blank?

        facility_info = {
          name: referral.referring_facility_name,
          phone: referral.referring_facility_phone,
          code: referral.referring_facility_code
        }

        address = referral.referring_facility_address
        if address.present? && address.values.any?(&:present?)
          facility_info[:address] = {
            street1: address[:street1],
            city: address[:city],
            state: address[:state],
            zip: address[:zip]
          }
        end

        facility_info
      end
    end
  end
end
