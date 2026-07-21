# frozen_string_literal: true

module ClaimantInfoHelpers
  def get_benefits(non33_benefit_types, non33_data, ch33_lts_data)
    return [] if non33_data.blank? && ch33_lts_data.blank?

    filtered_non33_data = non33_data.select do |eligibility|
      non33_benefit_types.include?(eligibility['benefit_type'])
    end

    non33 = map_non33(filtered_non33_data)
    ch33 = ch33(ch33_lts_data)

    non33 << ch33
  end

  def convert_to_months_and_days(original_days)
    months, days = original_days.divmod(30)
    days = original_days > 0.0 && original_days < 1.0 ? 1.0 : days.round(half: :even)
    { months:, days: }
  end

  def ch33(data)
    return {} if data.blank?

    benefit_type = data['benefit_or_source_type']

    result = {
      benefit_type:,
      amount_received: convert_to_months_and_days(data['ch33_original_entitled_days']),
      amount_used: convert_to_months_and_days(data['ch33_days_used']),
      amount_left: convert_to_months_and_days(data['ch33_days_remaining']),
      eligibility_percentage: data['percentage_benefit'],
      benefit_end_date: data['delimiting_date']
    }

    if benefit_type == 'CH33' && data['entitlement_transfers'].present?
      result[:amount_transferred] =
        convert_to_months_and_days(data['entitlement_transfers'].map do |obj|
          obj['transfer_out']
        end.sum)
    end

    result
  end

  def map_non33(non33_data)
    return [] if non33_data.blank?

    non33_data.map do |benefit|
      entitlement = benefit['entitlement_result']
      {
        benefit_type: benefit['benefit_type'],
        amount_received: convert_to_months_and_days(entitlement['orig_entitled_days']),
        amount_used: convert_to_months_and_days(entitlement['days_used']),
        amount_left: convert_to_months_and_days(entitlement['days_remaining']),
        benefit_end_date: benefit.dig('eligibility_result', 'delimiting_date')
      }
    end
  end

  def get_in_progress_flags(benefit_type, original_claims)
    return false if original_claims.blank?

    original_claims.any? { |claim| claim['benefit_or_source_type'] == benefit_type }
  end

  def get_received_date(benefit_type, original_claims)
    return nil if original_claims.blank?

    original_claim = original_claims.find do |claim|
      claim['benefit_or_source_type'] == benefit_type
    end

    original_claim&.[]('date_received')
  end
end
