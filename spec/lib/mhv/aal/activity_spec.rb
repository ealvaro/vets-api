# frozen_string_literal: true

require 'rails_helper'
require 'mhv/aal/activity'

RSpec.describe AAL::Activity do
  describe '.from_api' do
    let(:api_hash) do
      {
        'activityId' => 123,
        'userProfileId' => 456,
        'patientId' => 789,
        'action' => 'LOGIN',
        'status' => 'true',
        'performerType' => 'SELF',
        'activityType' => 'LOGIN_LOGOUT',
        'detailValue' => 'User logged in via Login.gov',
        'completionTime' => '2026-03-04T14:30:00Z'
      }
    end

    it 'maps camelCase API fields to snake_case attributes' do
      activity = described_class.from_api(api_hash)

      expect(activity.activity_id).to eq(123)
      expect(activity.user_profile_id).to eq(456)
      expect(activity.patient_id).to eq(789)
      expect(activity.action).to eq('LOGIN')
      expect(activity.status).to eq('true')
      expect(activity.performer_type).to eq('SELF')
      expect(activity.activity_type).to eq('LOGIN_LOGOUT')
      expect(activity.detail_value).to eq('User logged in via Login.gov')
      expect(activity.completion_time).to eq('2026-03-04T14:30:00Z')
    end

    it 'provides an id method for serialization' do
      activity = described_class.from_api(api_hash)
      expect(activity.id).to eq(123)
    end

    it 'handles missing optional fields gracefully' do
      minimal_hash = {
        'activityId' => 1,
        'action' => 'LOGIN',
        'activityType' => 'LOGIN_LOGOUT',
        'performerType' => 'SELF',
        'status' => 'true'
      }
      activity = described_class.from_api(minimal_hash)

      expect(activity.patient_id).to be_nil
      expect(activity.detail_value).to be_nil
      expect(activity.completion_time).to be_nil
    end
  end
end
