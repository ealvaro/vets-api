# frozen_string_literal: true

require 'rails_helper'
require_relative '../../spec_helper'

RSpec.describe AccreditedRepresentativePortal::DeleteOldForm21aAttachmentsJob, type: :job do
  subject(:job) { described_class.new }

  let(:application_id) { '12345' }
  let(:document_type) { 1 }
  let(:content_type) { 'application/pdf' }
  let(:mock_file) { double('file', delete: true) }

  around do |example|
    Timecop.freeze(Time.zone.local(2026, 7, 15, 12)) do
      example.run
    end
  end

  before do
    allow_any_instance_of(AccreditedRepresentativePortal::Form21aAttachment)
      .to receive(:get_file)
      .and_return(mock_file)
  end

  def create_attachment(guid: SecureRandom.uuid, created_at: 60.days.ago)
    create(
      :form_attachment,
      guid:,
      type: 'AccreditedRepresentativePortal::Form21aAttachment',
      created_at:
    )
  end

  def create_submission(
    form21a_attachment_guid:,
    latest_status:,
    succeeded_at: nil,
    last_attempted_at: nil
  )
    Form21aDocumentSubmission.create!(
      form_id: '21a',
      application_id:,
      form21a_attachment_guid:,
      document_type:,
      content_type:,
      latest_status:,
      succeeded_at:,
      last_attempted_at:
    )
  end

  def kept_uuids
    job.uuids_to_keep.pluck(:guid)
  end

  it 'inherits DeleteAttachmentJob' do
    expect(described_class.ancestors).to include(DeleteAttachmentJob)
  end

  describe '::ATTACHMENT_CLASSES' do
    it 'references the Form 21a attachment model name' do
      expect(described_class::ATTACHMENT_CLASSES).to eq(
        ['AccreditedRepresentativePortal::Form21aAttachment']
      )
    end
  end

  describe '::EXPIRATION_TIME' do
    it 'is explicitly set to 30 days' do
      expect(described_class::EXPIRATION_TIME).to eq(30.days)
    end
  end

  describe '#uuids_to_keep' do
    it 'returns an ActiveRecord relation' do
      expect(job.uuids_to_keep).to be_an(ActiveRecord::Relation)
    end

    it 'keeps an attachment that has no document submission' do
      attachment = create_attachment

      expect(kept_uuids).to include(attachment.guid)
    end

    it 'keeps attachments for non-reapable submission statuses' do
      attachments = %w[
        pending
        uploading
        failed_transient
        failed_permanent
      ].map do |latest_status|
        attachment = create_attachment

        create_submission(
          form21a_attachment_guid: attachment.guid,
          latest_status:,
          last_attempted_at: 60.days.ago
        )

        attachment
      end

      expect(kept_uuids).to include(
        *attachments.map(&:guid)
      )
    end

    it 'keeps a succeeded attachment still within the retention window' do
      attachment = create_attachment

      create_submission(
        form21a_attachment_guid: attachment.guid,
        latest_status: 'succeeded',
        succeeded_at: 30.days.ago,
        last_attempted_at: 30.days.ago
      )

      expect(kept_uuids).to include(attachment.guid)
    end

    it 'keeps an abandoned attachment still within the retention window' do
      attachment = create_attachment

      create_submission(
        form21a_attachment_guid: attachment.guid,
        latest_status: 'abandoned',
        last_attempted_at: 30.days.ago
      )

      expect(kept_uuids).to include(attachment.guid)
    end

    it 'keeps a succeeded attachment when succeeded_at is missing' do
      attachment = create_attachment

      create_submission(
        form21a_attachment_guid: attachment.guid,
        latest_status: 'succeeded',
        succeeded_at: nil,
        last_attempted_at: 60.days.ago
      )

      expect(kept_uuids).to include(attachment.guid)
    end

    it 'keeps an abandoned attachment when last_attempted_at is missing' do
      attachment = create_attachment

      create_submission(
        form21a_attachment_guid: attachment.guid,
        latest_status: 'abandoned',
        last_attempted_at: nil
      )

      expect(kept_uuids).to include(attachment.guid)
    end

    it 'does not keep a succeeded attachment past the retention window' do
      attachment = create_attachment

      create_submission(
        form21a_attachment_guid: attachment.guid,
        latest_status: 'succeeded',
        succeeded_at: 31.days.ago,
        last_attempted_at: 31.days.ago
      )

      expect(kept_uuids).not_to include(attachment.guid)
    end

    it 'does not keep an abandoned attachment past the retention window' do
      attachment = create_attachment

      create_submission(
        form21a_attachment_guid: attachment.guid,
        latest_status: 'abandoned',
        last_attempted_at: 31.days.ago
      )

      expect(kept_uuids).not_to include(attachment.guid)
    end

    it 'does not include attachments younger than the expiration time' do
      attachment = create_attachment(created_at: 29.days.ago)

      expect(kept_uuids).not_to include(attachment.guid)
    end
  end

  describe '#perform' do
    it 'deletes a lingering attachment for a succeeded submission past retention' do
      attachment = create_attachment(created_at: 31.days.ago)

      create_submission(
        form21a_attachment_guid: attachment.guid,
        latest_status: 'succeeded',
        succeeded_at: 31.days.ago,
        last_attempted_at: 31.days.ago
      )

      expect do
        job.perform
      end.to change(
        AccreditedRepresentativePortal::Form21aAttachment,
        :count
      ).by(-1)

      expect do
        attachment.reload
      end.to raise_error(ActiveRecord::RecordNotFound)
    end

    it 'is a no-op when a succeeded submission attachment is already gone' do
      create_submission(
        form21a_attachment_guid: SecureRandom.uuid,
        latest_status: 'succeeded',
        succeeded_at: 31.days.ago,
        last_attempted_at: 31.days.ago
      )

      expect { job.perform }.not_to raise_error
    end

    it 'deletes an attachment for an abandoned submission past retention' do
      attachment = create_attachment(created_at: 31.days.ago)

      create_submission(
        form21a_attachment_guid: attachment.guid,
        latest_status: 'abandoned',
        last_attempted_at: 31.days.ago
      )

      expect do
        job.perform
      end.to change(
        AccreditedRepresentativePortal::Form21aAttachment,
        :count
      ).by(-1)

      expect do
        attachment.reload
      end.to raise_error(ActiveRecord::RecordNotFound)
    end

    it 'keeps a recently abandoned attachment inside the retention window' do
      attachment = create_attachment(created_at: 60.days.ago)

      create_submission(
        form21a_attachment_guid: attachment.guid,
        latest_status: 'abandoned',
        last_attempted_at: 30.days.ago
      )

      expect do
        job.perform
      end.not_to change(
        AccreditedRepresentativePortal::Form21aAttachment,
        :count
      )

      expect(attachment.reload).to be_present
    end

    it 'keeps a recently succeeded attachment inside the retention window' do
      attachment = create_attachment(created_at: 60.days.ago)

      create_submission(
        form21a_attachment_guid: attachment.guid,
        latest_status: 'succeeded',
        succeeded_at: 30.days.ago,
        last_attempted_at: 30.days.ago
      )

      expect do
        job.perform
      end.not_to change(
        AccreditedRepresentativePortal::Form21aAttachment,
        :count
      )

      expect(attachment.reload).to be_present
    end

    %w[pending uploading failed_transient failed_permanent].each do |latest_status|
      it "does not delete an attachment for a #{latest_status} submission" do
        attachment = create_attachment(created_at: 60.days.ago)

        create_submission(
          form21a_attachment_guid: attachment.guid,
          latest_status:,
          last_attempted_at: 60.days.ago
        )

        expect do
          job.perform
        end.not_to change(
          AccreditedRepresentativePortal::Form21aAttachment,
          :count
        )

        expect(attachment.reload).to be_present
      end
    end

    it 'does not delete an old Form 21a attachment without a submission' do
      attachment = create_attachment(created_at: 60.days.ago)

      expect do
        job.perform
      end.not_to change(
        AccreditedRepresentativePortal::Form21aAttachment,
        :count
      )

      expect(attachment.reload).to be_present
    end

    it 'does not delete an attachment that is younger than the expiration time' do
      attachment = create_attachment(created_at: 29.days.ago)

      create_submission(
        form21a_attachment_guid: attachment.guid,
        latest_status: 'succeeded',
        succeeded_at: 31.days.ago,
        last_attempted_at: 31.days.ago
      )

      expect do
        job.perform
      end.not_to change(
        AccreditedRepresentativePortal::Form21aAttachment,
        :count
      )

      expect(attachment.reload).to be_present
    end
  end
end
