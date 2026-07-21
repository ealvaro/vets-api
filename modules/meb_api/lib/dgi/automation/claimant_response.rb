# frozen_string_literal: true

require 'dgi/response'
require 'dgi/claimant_info_helpers'

module MebApi
  module DGI
    module Automation
      class ClaimantResponse < MebApi::DGI::Response
        include ClaimantInfoHelpers

        attribute :claimant, Hash
        attribute :service_data, Hash, array: true
        attribute :ssn, String
        attribute :benefits, Hash, array: true
        attribute :has_ch_1606_original_claim_in_progress, Bool, default: false
        attribute :has_ch_30_original_claim_in_progress, Bool, default: false
        attribute :has_ch_33_original_claim_in_progress, Bool, default: false
        attribute :has_ch_35_original_claim_in_progress, Bool, default: false
        attribute :has_fry_original_claim_in_progress, Bool, default: false
        attribute :has_toe_original_claim_in_progress, Bool, default: false
        attribute :ch_1606_received_date, String
        attribute :ch_30_received_date, String
        attribute :ch_33_received_date, String
        attribute :ch_35_received_date, String
        attribute :fry_received_date, String
        attribute :toe_received_date, String

        def initialize(status, response = nil)
          attributes = {
            claimant: response.body['claimant'],
            service_data: response.body['service_data']
          }

          attributes = add_supplemental_coe_attributes(response, attributes) if Flipper.enabled?(:meb_supplemental_coe)

          super(status, attributes)
        end

        private

        def add_supplemental_coe_attributes(response, attributes)
          non33_data = response.body['non33_eligibilities']
          ch33_data = response.body['latest_ch33_eligibility']
          in_progress_originals = response.body['submission_pending_review_information']
          benefits = get_benefits(%w[CH30 CH35 CH1606], non33_data, ch33_data)
          {
            **attributes,
            benefits:,
            has_ch_1606_original_claim_in_progress: get_in_progress_flags('CH1606', in_progress_originals),
            has_ch_30_original_claim_in_progress: get_in_progress_flags('CH30', in_progress_originals),
            has_ch_35_original_claim_in_progress: get_in_progress_flags('CH35', in_progress_originals),
            has_ch_33_original_claim_in_progress: get_in_progress_flags('CH33', in_progress_originals),
            has_fry_original_claim_in_progress: get_in_progress_flags('Fry', in_progress_originals),
            has_toe_original_claim_in_progress: get_in_progress_flags('Toe', in_progress_originals),
            ch_1606_received_date: get_received_date('CH1606', in_progress_originals),
            ch_30_received_date: get_received_date('CH30', in_progress_originals),
            ch_35_received_date: get_received_date('CH35', in_progress_originals),
            ch_33_received_date: get_received_date('CH33', in_progress_originals),
            fry_received_date: get_received_date('Fry', in_progress_originals),
            toe_received_date: get_received_date('Toe', in_progress_originals)
          }
        end
      end
    end
  end
end
