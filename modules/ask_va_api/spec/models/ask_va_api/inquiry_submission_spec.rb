# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AskVAApi::InquirySubmission, type: :model do
  describe 'associations' do
    it { is_expected.to have_many(:inquiry_submission_checkpoints) }
  end

  describe 'validations' do
    it { is_expected.to validate_presence_of(:request_id) }
  end
end
