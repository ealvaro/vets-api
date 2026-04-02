# frozen_string_literal: true

module Mobile
  module V0
    class ReferralListSerializer
      include JSONAPI::Serializer

      set_id :uuid
      set_type :referrals

      attribute :category_of_care
      attribute :referral_number
      attribute :referral_consult_id
      attribute :uuid
      attribute :station_id

      attribute :expiration_date do |referral|
        referral.expiration_date&.strftime('%Y-%m-%d')
      end

      # Override to handle nil collection
      def serializable_hash(...)
        return { data: [] } unless @resource.is_a?(Array)

        super
      end
    end
  end
end
