# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AskVAApi::Inquiries::Checkpoint::Base do
  describe '#call' do
    let!(:crm_response_payload) do
      {
        Data: {
          InquiryNumber: 'A-20250131-309217',
          ListOfAttachments: [
            {
              FileId: '2a132826-35e2-ef11-8eea-001dd809b958',
              FileName: 'example.pdf',
              ErrorMessage: nil
            }
          ]
        },
        Message: nil,
        ExceptionOccurred: false,
        ExceptionMessage: nil,
        StatusCode: 200,
        AssociatedRecordId: 'A-20250131-309217',
        MessageId: '8a19483d-e512-486e-ad97-8e12055080bd'
      }
    end
    let(:crm_response_expected_payload) do
      crm_response_payload.deep_dup.tap do |payload|
        payload[:Data][:AttachmentCount] = payload[:Data][:ListOfAttachments].count
      end
    end
    let(:crm_failure_payload) do
      {
        Data: nil,
        Message: 'Data Validation: missing InquiryCategory',
        ExceptionOccurred: true,
        ExceptionMessage: 'Data Validation: missing InquiryCategory',
        MessageId: 'cb0dd954-ef25-4e56-b0d9-41925e5a190c'
      }
    end

    context 'when called via the inbound checkpoint class' do
      let(:checkpoint_class) { AskVAApi::Inquiries::Checkpoint::Inbound }
      let(:request_id) { Faker::Internet.uuid }
      let(:payload) do
        {
          question: 'Example question',
          select_category: 'Health care',
          files: [
            { file_name: 'example.pdf', file_content: 'example_content' },
            { file_name: 'another_example.pdf', file_content: 'another_example_content' }
          ]
        }
      end
      let(:expected_payload) do
        {
          question: 'Example question',
          select_category: 'Health care',
          attachment_count: 2
        }
      end

      it 'creates a parent submission record and an inbound checkpoint record with a normalized payload' do
        expect do
          checkpoint_class.new.call(request_id:, payload:)
        end
          .to change(AskVAApi::InquirySubmission, :count).by(1)
          .and change(AskVAApi::InquirySubmissionCheckpoint, :count).by(1)

        inquiry_submission = AskVAApi::InquirySubmission.last
        checkpoint = AskVAApi::InquirySubmissionCheckpoint.last

        expect(checkpoint.inquiry_submission).to eq(inquiry_submission)
        expect(checkpoint.checkpoint_type).to eq('inbound_submission')
        expect(checkpoint.payload).to eq(expected_payload.deep_stringify_keys)
      end
    end

    context 'when called via the outbound checkpoint class and a parent inquiry submission record is found' do
      let(:checkpoint_class) { AskVAApi::Inquiries::Checkpoint::Outbound }
      let!(:inquiry_submission) { create(:ask_va_api_inquiry_submission) }
      let(:request_id) { inquiry_submission.request_id }
      let(:payload) do
        {
          InquiryCategory: '73524deb-d864-eb11-bb24-000d3a579c45',
          ListOfAttachments: [
            { FileName: 'example.pdf', FileContent: 'example_content' }
          ]
        }
      end
      let(:expected_payload) do
        {
          InquiryCategory: '73524deb-d864-eb11-bb24-000d3a579c45',
          AttachmentCount: 1
        }
      end

      it 'creates an associated outbound checkpoint record with a normalized payload' do
        expect do
          checkpoint_class.new.call(request_id:, payload:)
        end
          .to change(AskVAApi::InquirySubmissionCheckpoint, :count).by(1)
          .and not_change(AskVAApi::InquirySubmission, :count)

        checkpoint = AskVAApi::InquirySubmissionCheckpoint.last

        expect(checkpoint.inquiry_submission).to eq(inquiry_submission)
        expect(checkpoint.checkpoint_type).to eq('outbound_submission')
        expect(checkpoint.payload).to eq(expected_payload.deep_stringify_keys)
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
        expect(checkpoint.payload).to eq(payload.deep_stringify_keys)
      end
    end

    context 'when called via the crm response checkpoint class and a parent inquiry submission record is found' do
      let(:checkpoint_class) { AskVAApi::Inquiries::Checkpoint::CrmResponse }
      let!(:inquiry_submission) { create(:ask_va_api_inquiry_submission) }
      let(:request_id) { inquiry_submission.request_id }
      let(:payload) { crm_response_payload.deep_dup }

      it 'creates an associated crm response checkpoint record and updates the parent record' do
        expect do
          checkpoint_class.new.call(request_id:, payload:)
        end
          .to change(AskVAApi::InquirySubmissionCheckpoint, :count).by(1)
          .and change { inquiry_submission.reload.crm_message_id }.from(nil).to(payload[:MessageId])
          .and change { inquiry_submission.reload.inquiry_number }.from(nil).to(payload[:Data][:InquiryNumber])
          .and not_change(AskVAApi::InquirySubmission, :count)

        checkpoint = AskVAApi::InquirySubmissionCheckpoint.last

        expect(checkpoint.inquiry_submission).to eq(inquiry_submission)
        expect(checkpoint.checkpoint_type).to eq('crm_response')
        expect(checkpoint.payload).to eq(crm_response_expected_payload.deep_stringify_keys)
      end
    end

    context 'when called via the crm response checkpoint class and a parent inquiry submission record is not found' do
      let(:checkpoint_class) { AskVAApi::Inquiries::Checkpoint::CrmResponse }
      let(:request_id) { Faker::Internet.uuid }
      let(:payload) { crm_response_payload.deep_dup }

      it 'creates a parent inquiry submission, creates the checkpoint, and records the response identifiers' do
        expect do
          checkpoint_class.new.call(request_id:, payload:)
        end
          .to change(AskVAApi::InquirySubmission, :count).by(1)
          .and change(AskVAApi::InquirySubmissionCheckpoint, :count).by(1)

        inquiry_submission = AskVAApi::InquirySubmission.last
        checkpoint = AskVAApi::InquirySubmissionCheckpoint.last

        expect(inquiry_submission).to have_attributes(
          crm_message_id: payload[:MessageId],
          inquiry_number: payload[:Data][:InquiryNumber]
        )
        expect(checkpoint.inquiry_submission).to eq(inquiry_submission)
        expect(checkpoint.checkpoint_type).to eq('crm_response')
        expect(checkpoint.payload).to eq(crm_response_expected_payload.deep_stringify_keys)
      end
    end

    context 'when called via the crm response checkpoint class and the CRM response has no Data' do
      let(:checkpoint_class) { AskVAApi::Inquiries::Checkpoint::CrmResponse }
      let!(:inquiry_submission) { create(:ask_va_api_inquiry_submission) }
      let(:request_id) { inquiry_submission.request_id }
      let(:payload) { crm_failure_payload.deep_dup }

      it 'persists the payload without raising and updates only the crm message id' do
        expect do
          checkpoint_class.new.call(request_id:, payload:)
        end
          .to change(AskVAApi::InquirySubmissionCheckpoint, :count).by(1)
          .and change { inquiry_submission.reload.crm_message_id }.from(nil).to(payload[:MessageId])
          .and not_change { inquiry_submission.reload.inquiry_number }
          .and not_change(AskVAApi::InquirySubmission, :count)

        checkpoint = AskVAApi::InquirySubmissionCheckpoint.last

        expect(checkpoint.inquiry_submission).to eq(inquiry_submission)
        expect(checkpoint.checkpoint_type).to eq('crm_response')
        expect(checkpoint.payload).to eq(payload.deep_stringify_keys)
      end
    end
  end
end
