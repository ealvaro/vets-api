# frozen_string_literal: true

module MebApi
  module DGI
    module ClaimantInfoHelpers # rubocop:disable Metrics/ModuleLength
      def get_benefits(non33_benefit_types, cs_claimant_data, ch33_lts_data, coe_information)
        return [] if cs_claimant_data.blank?

        claimant_id = cs_claimant_data['id']
        eligibility_results = cs_claimant_data['eligibility_results']
        entitlement_results = cs_claimant_data['entitlement_results']

        non33_eligibilities = eligibility_results.select do |result|
          non33_benefit_types.include?(result['benefit_type'])
        end
        non33_entitlements = entitlement_results.select do |result|
          non33_benefit_types.include?(result['benefit_type'])
        end

        non33 = map_non33(claimant_id, non33_eligibilities, non33_entitlements, coe_information)
        ch33 = map_ch33(claimant_id, ch33_lts_data, coe_information)

        non33 + ch33
      end

      def convert_to_months_and_days(days)
        months, days = days.divmod(30)
        days = days > 0.0 && days < 1.0 ? 1.0 : days.round(half: :even)
        { months:, days: }
      end

      def map_ch33(claimant_id, lts_data, coe_information)
        return [] if [lts_data, coe_information].any?(&:blank?)

        categorize_ch33_data(lts_data,
                             coe_information) => { toe_sponsor_data:, toe_dependent_data:, self_data:, fry_data: }

        [
          ch33_hash(claimant_id, self_data),
          ch33_hash(claimant_id, toe_sponsor_data, is_toe_sponsor: true),
          ch33_hash(claimant_id, toe_dependent_data),
          ch33_hash(claimant_id, fry_data)
        ].compact_blank
      end

      def categorize_ch33_data(lts_data, coe_information)
        toe_sponsor_data = {}
        toe_dependent_data = {}
        self_data = {}
        fry_data = {}
        # Filters out ineligible claims
        lts_data.each do |benefit|
          claim = coe_information.find do |c|
            c['benefit_or_source_type'] == benefit['benefit_or_source_type']
          end
          next if claim&.[]('is_eligible').blank?

          case benefit['benefit_or_source_type']
          when 'CH33'
            toe_sponsor_data = { eligibility: benefit, coe: claim } if benefit['entitlement_transfers'].present?
            self_data = { eligibility: benefit, coe: claim } if benefit['entitlement_transfers'].blank?
          when 'Toe'
            toe_dependent_data = { eligibility: benefit, coe: claim }
          when 'Fry'
            fry_data = { eligibility: benefit, coe: claim }
          end
        end

        { toe_sponsor_data:, toe_dependent_data:, self_data:, fry_data: }
      end

      def ch33_hash(claimant_id, data, is_toe_sponsor: false)
        return {} if data.blank?

        claim_id = data.dig(:coe, 'wp_key')
        benefit_type = data.dig(:eligibility, 'benefit_or_source_type')

        result = {
          benefit_type:,
          amount_received: convert_to_months_and_days(data.dig(:eligibility, 'ch33_original_entitled_days')),
          amount_used: convert_to_months_and_days(data.dig(:eligibility, 'ch33_days_used')),
          amount_left: convert_to_months_and_days(data.dig(:eligibility, 'ch33_days_remaining')),
          eligibility_percentage: data.dig(:eligibility, 'percentage_benefit'),
          benefit_end_date: data.dig(:eligibility, 'delimiting_date'),
          coe_issued_date: data.dig(:coe, 'date_authorized'),
          coe_letter: get_coe_letter(claim_id, claimant_id, benefit_type)
        }

        if is_toe_sponsor
          result[:amount_transferred] =
            convert_to_months_and_days(data.dig(:eligibility, 'entitlement_transfers').map do |obj|
              obj['transfer_out']
            end.sum)
        end

        result
      end

      def get_coe_letter(claim_id, claimant_id, benefit_type)
        begin
          coe_letter_response = MebApi::DGI::Letters::Service.new(nil).get_claim_letter_by_claim_id(
            claim_id,
            claimant_id, benefit_type
          )
        rescue
          return nil
        end

        if coe_letter_response.status == 200
          response_body = coe_letter_response.body
          mime_type = Marcel::MimeType.for(StringIO.new(response_body))
          base64_data = Base64.strict_encode64(response_body)
          "data:#{mime_type};base64,#{base64_data}"
        end
      end

      def map_non33(claimant_id, eligibility_results, entitlement_results, coe_information)
        return [] if [eligibility_results, entitlement_results, coe_information].any?(&:blank?)

        # Claimant can only have one eligibility/entitlement per benefit type/claim
        eligibility_results.filter_map do |eligibility|
          entitlement_results.filter_map do |entitlement|
            coe_information.filter_map do |ci|
              benefit_type = eligibility['benefit_type']
              if benefit_type == entitlement['benefit_type'] &&
                 benefit_type == ci['benefit_or_source_type'] && ci['is_eligible']
                {
                  benefit_type:,
                  amount_received: convert_to_months_and_days(entitlement['orig_entitled_days']),
                  amount_used: convert_to_months_and_days(entitlement['days_used']),
                  amount_left: convert_to_months_and_days(entitlement['days_remaining']),
                  benefit_end_date: eligibility.dig('eligibility_period', 'delimiting_date'),
                  coe_issued_date: ci['date_authorized'],
                  coe_letter: get_coe_letter(ci['claim_id'] || ci['wp_key'], claimant_id, benefit_type)
                }
              end
            end
          end
        end.flatten
      end

      def get_in_progress_flags(benefit_type, original_claims)
        return false if original_claims.blank?

        original_claim = original_claims.find do |claim|
          claim['benefit_or_source_type'] == benefit_type
        end

        original_claim&.[]('is_in_progress') == true
      end

      def get_received_date(benefit_type, original_claims)
        return nil if original_claims.blank?

        original_claim = original_claims.find do |claim|
          claim['benefit_or_source_type'] == benefit_type
        end

        original_claim&.[]('date_received')
      end
    end
  end
end
