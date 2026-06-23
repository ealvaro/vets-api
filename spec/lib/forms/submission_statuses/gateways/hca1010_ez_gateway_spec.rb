# frozen_string_literal: true

require 'rails_helper'
require 'forms/submission_statuses/gateways/hca1010_ez_gateway'

describe Forms::SubmissionStatuses::Gateways::Hca1010EzGateway,
         feature: :form_submission,
         team_owner: :health_apps_backend do
  let(:user_account) { create(:user_account) }
  let(:created_at) { (DateTime.current - 15.days).to_s }
  let(:updated_at) { (DateTime.current - 14.days).to_s }

  describe '#submissions' do
    it 'returns the user' do
      gateway = described_class.new(user_account:)

      expect(gateway.submissions).to eq([user_account])
    end
  end

  describe '#api_statuses' do
    it 'returns enrolled status as received and nil errors on success' do
      result = {
        application_date: created_at,
        effective_date: updated_at,
        enrollment_date: '2019-01-02T21:58:55.000-06:00',
        preferred_facility: '988 - DAYT20',
        parsed_status: :enrolled,
        priority_group: 'Group 3',
        can_submit_financial_info: true
      }
      expect(HealthCareApplication).to receive(:enrollment_status).with(user_account.icn, true).and_return(result)
      gateway = described_class.new(user_account:)

      expected_status = {
        id: user_account.id,
        status: :vbms,
        created_at:,
        updated_at:
      }
      expect(gateway.api_statuses([user_account])).to eq([[expected_status], nil])
    end

    it 'returns pending status as in_progress and nil errors on success' do
      result = {
        application_date: created_at,
        effective_date: updated_at,
        enrollment_date: '2019-01-02T21:58:55.000-06:00',
        preferred_facility: '988 - DAYT20',
        parsed_status: :pending_other,
        priority_group: 'Group 3',
        can_submit_financial_info: true
      }
      expect(HealthCareApplication).to receive(:enrollment_status).with(user_account.icn, true).and_return(result)
      gateway = described_class.new(user_account:)

      expected_status = {
        id: user_account.id,
        status: :in_progress,
        created_at:,
        updated_at:
      }
      expect(gateway.api_statuses([user_account])).to eq([[expected_status], nil])
    end

    it 'returns unexpected status as nil and nil errors on success' do
      result = {
        application_date: created_at,
        effective_date: updated_at,
        enrollment_date: '2019-01-02T21:58:55.000-06:00',
        preferred_facility: '988 - DAYT20',
        parsed_status: :status_we_do_not_recognize,
        priority_group: 'Group 3',
        can_submit_financial_info: true

      }
      expect(HealthCareApplication).to receive(:enrollment_status).with(user_account.icn, true).and_return(result)
      gateway = described_class.new(user_account:)

      expect(gateway.api_statuses([user_account])).to eq([nil, nil])
    end

    it 'returns normalized error with correct status on failure' do
      expect(HealthCareApplication)
        .to receive(:enrollment_status)
        .with(user_account.icn, true)
        .and_raise(Common::Exceptions::GatewayTimeout)
      gateway = described_class.new(user_account:)

      statuses, errors = gateway.api_statuses([user_account])
      expect(statuses).to be_nil
      expect(errors).to be_an(Array)
      expect(errors.first).to include(
        status: 504,
        source: 'hca1010_ez',
        detail: 'Gateway timeout'
      )
    end
  end
end
