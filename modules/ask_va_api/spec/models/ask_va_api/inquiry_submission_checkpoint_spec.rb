# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AskVAApi::InquirySubmissionCheckpoint, type: :model do
  describe 'associations' do
    it { is_expected.to belong_to(:inquiry_submission) }
  end

  describe 'validations' do
    it { is_expected.to validate_presence_of(:checkpoint_type) }

    it do
      expect(subject).to validate_inclusion_of(:checkpoint_type)
        .in_array(AskVAApi::InquirySubmissionCheckpoint::VALID_CHECKPOINTS)
    end

    it { is_expected.to validate_presence_of(:ask_va_inquiry_submission_id) }
    it { is_expected.to validate_presence_of(:payload) }
  end
end
