# frozen_string_literal: true

require 'rails_helper'

RSpec.describe CaveSubmissionPurgeJob, type: :job do
  it 'deletes submissions past their delete_date and keeps unexpired ones' do
    expired = CaveSubmission.create!(cave_response: '{}', delete_date: 1.day.ago)
    current = CaveSubmission.create!(cave_response: '{}', delete_date: 1.day.from_now)

    described_class.new.perform

    expect(CaveSubmission.exists?(expired.id)).to be(false)
    expect(CaveSubmission.exists?(current.id)).to be(true)
  end

  it 'does not raise when there is nothing to purge' do
    expect { described_class.new.perform }.not_to raise_error
  end

  it 'emits pii.deleting and pii.deleted audit events carrying only record ids' do
    expired = CaveSubmission.create!(cave_response: '{}', delete_date: 1.day.ago)
    seen = []
    collector = ->(name, *_args, payload) { seen << [name, payload] }

    ActiveSupport::Notifications.subscribed(collector, /pii\.delet/) do
      described_class.new.perform
    end

    expect(seen.map(&:first)).to contain_exactly('pii.deleting', 'pii.deleted')
    expect(seen.last.last[:cave_submission_ids]).to include(expired.id)
    expect(seen.last.last[:record_type]).to eq('CaveSubmission')
  end
end
