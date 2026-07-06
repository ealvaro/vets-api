# frozen_string_literal: true

class ToeClaimantInfoSerializer
  include JSONAPI::Serializer

  attributes :claimant, :service_data, :toe_sponsors

  attribute :ssn, if: proc { |_r| Flipper.enabled?(:meb_supplemental_coe) }
  attribute :benefits, if: proc { |_r| Flipper.enabled?(:meb_supplemental_coe) }
  attribute :has_ch_33_original_claim_in_progress, if: proc { |_r| Flipper.enabled?(:meb_supplemental_coe) }
  attribute :has_ch_35_original_claim_in_progress, if: proc { |_r| Flipper.enabled?(:meb_supplemental_coe) }
  attribute :has_fry_original_claim_in_progress, if: proc { |_r| Flipper.enabled?(:meb_supplemental_coe) }
  attribute :has_toe_original_claim_in_progress, if: proc { |_r| Flipper.enabled?(:meb_supplemental_coe) }
  attribute :ch_33_received_date, if: proc { |_r| Flipper.enabled?(:meb_supplemental_coe) }
  attribute :ch_35_received_date, if: proc { |_r| Flipper.enabled?(:meb_supplemental_coe) }
  attribute :fry_received_date, if: proc { |_r| Flipper.enabled?(:meb_supplemental_coe) }
  attribute :toe_received_date, if: proc { |_r| Flipper.enabled?(:meb_supplemental_coe) }

  set_id { '' }
end
