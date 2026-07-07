# frozen_string_literal: true

require 'rails_helper'

RSpec.describe CaveSubmission, type: :model do
  describe 'associations' do
    it { is_expected.to belong_to(:saved_claim).optional }
  end

  describe 'validations' do
    it 'is invalid without a cave_response' do
      submission = described_class.new(cave_response: nil)
      expect(submission).not_to be_valid
      expect(submission.errors[:cave_response]).to include("can't be blank")
    end

    it 'is invalid when cave_response is not valid JSON' do
      submission = described_class.new(cave_response: 'not-json')
      expect(submission).not_to be_valid
      expect(submission.errors[:cave_response]).to include('must be valid JSON')
    end

    it 'does not persist a malformed cave_response' do
      submission = described_class.new(cave_response: 'not-json')
      expect(submission.save).to be(false)
      expect { submission.save! }.to raise_error(ActiveRecord::RecordInvalid)
    end

    it 'is valid with a well-formed JSON object cave_response' do
      submission = described_class.new(cave_response: { 'FIRST_NAME' => 'Ada' }.to_json)
      expect(submission).to be_valid
    end
  end

  describe '#parsed_response' do
    let(:payload) { { 'answer' => 'yes', 'score' => 42 } }
    let(:submission) { described_class.new(cave_response: payload.to_json) }

    it 'parses the JSON cave_response' do
      expect(submission.parsed_response).to eq(payload)
    end

    it 'memoizes the result' do
      result1 = submission.parsed_response
      result2 = submission.parsed_response
      expect(result1).to be(result2)
    end

    it 'returns nil and logs when cave_response is corrupt JSON' do
      submission = described_class.new(cave_response: 'not-json')
      allow(Rails.logger).to receive(:warn)

      expect(submission.parsed_response).to be_nil
      expect(Rails.logger).to have_received(:warn)
        .with('CaveSubmission#parsed_response: corrupt cave_response JSON', hash_including(:error))
    end
  end

  describe 'retention' do
    it 'sets a delete_date on create based on RETENTION_DAYS' do
      submission = described_class.create!(cave_response: '{}')
      expect(submission.delete_date).to be_within(1.day).of(CaveSubmission::RETENTION_DAYS.days.from_now)
    end

    it 'does not overwrite an explicitly provided delete_date' do
      explicit = 5.days.from_now
      submission = described_class.create!(cave_response: '{}', delete_date: explicit)
      expect(submission.delete_date).to be_within(1.second).of(explicit)
    end
  end

  describe '#parsed_change_log' do
    it 'returns an empty array when no change log is stored' do
      expect(described_class.new.parsed_change_log).to eq([])
    end

    it 'parses and round-trips the encrypted change log' do
      records = [{ 'field' => 'VETERAN_NAME', 'label' => 'Veteran name', 'ocr_value' => 'JON', 'user_value' => 'John' }]
      submission = described_class.create!(cave_response: '{}', change_log: records.to_json)
      expect(submission.reload.parsed_change_log).to eq(records)
    end

    it 'returns an empty array when the stored change log is not valid JSON' do
      submission = described_class.create!(cave_response: '{}', change_log: 'not-json')
      expect(submission.reload.parsed_change_log).to eq([])
    end
  end
end
