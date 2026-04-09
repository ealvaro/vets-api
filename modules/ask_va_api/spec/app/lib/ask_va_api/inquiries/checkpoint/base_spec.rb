# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AskVAApi::Inquiries::Checkpoint::Base do
  describe '#call' do
    context 'when called via the inbound checkpoint class' do
      let(:checkpoint_class) { AskVAApi::Inquiries::Checkpoint::Inbound }
      let(:request_id) { Faker::Internet.uuid }
      let(:payload) { { foo: 'bar' } }

      it 'creates a parent submission record and an inbound checkpoint record' do
        expect do
          checkpoint_class.new.call(request_id:, payload:)
        end
          .to change(AskVAApi::InquirySubmission, :count).by(1)
          .and change(AskVAApi::InquirySubmissionCheckpoint, :count).by(1)

        inquiry_submission = AskVAApi::InquirySubmission.last
        checkpoint = AskVAApi::InquirySubmissionCheckpoint.last

        expect(checkpoint.inquiry_submission).to eq(inquiry_submission)
        expect(checkpoint.checkpoint_type).to eq('inbound_submission')
        expect(checkpoint.payload).to eq(payload.stringify_keys)
      end
    end

    context 'when called via the outbound checkpoint class and a parent inquiry submission record is found' do
      let(:checkpoint_class) { AskVAApi::Inquiries::Checkpoint::Outbound }
      let!(:inquiry_submission) { create(:ask_va_api_inquiry_submission) }
      let(:request_id) { inquiry_submission.request_id }
      let(:payload) { { foo: 'bar' } }

      it 'creates an associated outbound checkpoint record' do
        expect do
          checkpoint_class.new.call(request_id:, payload:)
        end
          .to change(AskVAApi::InquirySubmissionCheckpoint, :count).by(1)
          .and not_change(AskVAApi::InquirySubmission, :count)

        checkpoint = AskVAApi::InquirySubmissionCheckpoint.last

        expect(checkpoint.inquiry_submission).to eq(inquiry_submission)
        expect(checkpoint.checkpoint_type).to eq('outbound_submission')
        expect(checkpoint.payload).to eq(payload.stringify_keys)
      end
    end

    context 'when called via the outbound checkpoint class and a parent inquiry submission record is not found' do
      let(:checkpoint_class) { AskVAApi::Inquiries::Checkpoint::Outbound }
      let(:request_id) { Faker::Internet.uuid }
      let(:payload) { { foo: 'bar' } }

      it 'creates the parent inquiry submission record and an outbound checkpoint record' do
        expect do
          checkpoint_class.new.call(request_id:, payload:)
        end
          .to change(AskVAApi::InquirySubmission, :count).by(1)
          .and change(AskVAApi::InquirySubmissionCheckpoint, :count).by(1)

        inquiry_submission = AskVAApi::InquirySubmission.last
        checkpoint = AskVAApi::InquirySubmissionCheckpoint.last

        expect(checkpoint.inquiry_submission).to eq(inquiry_submission)
        expect(checkpoint.checkpoint_type).to eq('outbound_submission')
        expect(checkpoint.payload).to eq(payload.stringify_keys)
      end
    end
  end
end
