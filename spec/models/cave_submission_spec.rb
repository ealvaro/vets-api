# frozen_string_literal: true

require 'rails_helper'

RSpec.describe CaveSubmission, type: :model do
  describe 'associations' do
    it { is_expected.to belong_to(:saved_claim).optional }
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
  end
end
