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
          coe_information = response.body['coe_information']
          benefits = get_benefits(%w[CH30 CH35 CH1606], response.body['cs_claimant'],
                                  response.body['latest_ch33_eligibilites'], coe_information)
          {
            **attributes,
            benefits:,
            has_ch_1606_original_claim_in_progress: get_in_progress_flags('CH1606', coe_information),
            has_ch_30_original_claim_in_progress: get_in_progress_flags('CH30', coe_information),
            has_ch_35_original_claim_in_progress: get_in_progress_flags('CH35', coe_information),
            has_ch_33_original_claim_in_progress: get_in_progress_flags('CH33', coe_information),
            has_fry_original_claim_in_progress: get_in_progress_flags('Fry', coe_information),
            has_toe_original_claim_in_progress: get_in_progress_flags('Toe', coe_information),
            ch_1606_received_date: get_received_date('CH1606', coe_information),
            ch_30_received_date: get_received_date('CH30', coe_information),
            ch_35_received_date: get_received_date('CH35', coe_information),
            ch_33_received_date: get_received_date('CH33', coe_information),
            fry_received_date: get_received_date('Fry', coe_information),
            toe_received_date: get_received_date('Toe', coe_information)
          }
        end
      end
    end
  end
end
