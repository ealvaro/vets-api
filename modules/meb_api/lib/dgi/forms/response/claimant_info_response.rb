# frozen_string_literal: true

require 'dgi/response'
require 'dgi/claimant_info_helpers'

module MebApi
  module DGI
    module Forms
      class ClaimantResponse < MebApi::DGI::Response
        include ClaimantInfoHelpers

        attribute :claimant, Hash
        attribute :toe_sponsors, Hash
        attribute :service_data, Hash, array: true
        attribute :ssn, String
        attribute :benefits, Hash, array: true
        attribute :has_ch_33_original_claim_in_progress, Bool, default: false
        attribute :has_ch_35_original_claim_in_progress, Bool, default: false
        attribute :has_fry_original_claim_in_progress, Bool, default: false
        attribute :has_toe_original_claim_in_progress, Bool, default: false
        attribute :ch_33_received_date, String
        attribute :ch_35_received_date, String
        attribute :fry_received_date, String
        attribute :toe_received_date, String

        def initialize(status, response = nil)
          attributes = {
            claimant: response.body['claimant'],
            toe_sponsors: response.body['toe_sponsors'],
            service_data: response.body['service_data']
          }

          if Flipper.enabled?(:meb_supplemental_coe)
            coe_information = response.body['coe_information']
            benefits = get_benefits(['CH35'], response.body['cs_claimant'], response.body['latest_ch33_eligibilites'],
                                    coe_information)
            attributes[:benefits] = benefits
            attributes[:has_ch_35_original_claim_in_progress] = get_in_progress_flags('CH35', coe_information)
            attributes[:has_ch_33_original_claim_in_progress] = get_in_progress_flags('CH33', coe_information)
            attributes[:has_fry_original_claim_in_progress] = get_in_progress_flags('Fry', coe_information)
            attributes[:has_toe_original_claim_in_progress] = get_in_progress_flags('Toe', coe_information)
            attributes[:ch_35_received_date] = get_received_date('CH35', coe_information)
            attributes[:ch_33_received_date] = get_received_date('CH33', coe_information)
            attributes[:fry_received_date] = get_received_date('Fry', coe_information)
            attributes[:toe_received_date] = get_received_date('Toe', coe_information)
          end

          super(status, attributes)
        end
      end
    end
  end
end
