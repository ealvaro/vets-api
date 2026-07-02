# frozen_string_literal: true

require 'rails_helper'

RSpec.describe VAOS::V2::ReferralMissingDataMonitor do
  let(:user) { build(:user, uuid: 'user-uuid-123') }

  describe '.log_list' do
    let(:complete_referral) { build(:ccra_referral_list_entry) }
    let(:incomplete_referral) do
      build(:ccra_referral_list_entry,
            category_of_care: nil,
            referral_expiration_date: nil,
            station_id: '528A6')
    end

    it 'does nothing when all referrals are complete' do
      expect(Rails.logger).not_to receive(:error)
      expect(StatsD).not_to receive(:increment)

      described_class.log_list([complete_referral], user:)
    end

    it 'logs and increments the list missing_data metric for incomplete entries' do
      expect(Rails.logger).to receive(:error).with(
        described_class::LIST_LOG_MESSAGE,
        {
          missing_data: %w[category_of_care expiration_date],
          station_id: '528A6',
          user_uuid: user.uuid
        }
      )
      expect(StatsD).to receive(:increment).with(
        described_class::LIST_METRIC,
        tags: [
          'service:community_care_appointments',
          'station_id:528A6'
        ]
      )

      described_class.log_list([incomplete_referral], user:)
    end
  end

  describe '.log_detail' do
    let(:complete_referral) { build(:ccra_referral_detail) }
    let(:incomplete_referral) do
      build(:ccra_referral_detail, referral_number:).tap do |referral|
        referral.instance_variable_set(:@referring_facility_code, nil)
        referral.instance_variable_set(:@provider_npi, '')
      end
    end
    let(:referral_number) { '5682' }

    it 'does nothing when the referral is complete' do
      expect(Rails.logger).not_to receive(:error)
      expect(StatsD).not_to receive(:increment)

      described_class.log_detail(complete_referral, user:)
    end

    it 'logs and increments the detail missing_data metric for incomplete referrals' do
      expect(Rails.logger).to receive(:error).with(
        described_class::DETAIL_LOG_MESSAGE,
        {
          missing_data: %w[referring_facility_code referral_provider_npi],
          station_id: '528A6',
          user_uuid: user.uuid
        }
      )
      expect(StatsD).to receive(:increment).with(
        described_class::DETAIL_METRIC,
        tags: [
          'service:community_care_appointments',
          'station_id:528A6'
        ]
      )

      described_class.log_detail(incomplete_referral, user:)
    end
  end
end
