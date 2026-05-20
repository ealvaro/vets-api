# frozen_string_literal: true

require 'rails_helper'
require 'rake'
require SimpleFormsApi::Engine.root.join('spec', 'spec_helper.rb')

RSpec.describe 'simple_forms_api:send_expiration_emails', type: :task do
  let(:task) { Rake::Task['simple_forms_api:send_expiration_emails'] }
  let(:notification_email) { double(send: nil) }

  before(:all) do
    Rake::Task.define_task(:environment)
    unless Rake::Task.task_defined?('simple_forms_api:send_expiration_emails')
      load File.expand_path('../../lib/tasks/send_expiration_emails.rake', __dir__)
    end
  end

  before do
    # PR 27541 is merged; this should exist in CI now.
    expect(
      FormSubmission.connection.column_exists?(:form_submissions, :expiration_email_sent_at)
    ).to be(true)

    # Ensure template lookup succeeds by default (Email#send no-ops if template_id missing)
    allow(Settings.vanotify.services.va_gov.template_id).to receive(:[])
      .and_call_original
    allow(Settings.vanotify.services.va_gov.template_id).to receive(:[])
      .with('form40_1330m_expiration_email')
      .and_return('form40_1330m_expiration_email_template_id')

    # Default flipper to enabled unless overridden
    allow(Flipper).to receive(:enabled?).and_call_original
    allow(Flipper).to receive(:enabled?).with(:form40_1330m_expiration_email).and_return(true)
  end

  after do
    task.reenable
  end

  def run_task
    task.reenable
    task.invoke
  end

  context 'when a 40-1330M submission has passed the expiration threshold and no email has been sent' do
    let(:form_submission) do
      create(
        :form_submission,
        form_type: '40-1330M',
        created_at: 31.days.ago,
        expiration_email_sent_at: nil,
        form_data: { 'applicantEmail' => 'applicant@example.com' }.to_json
      )
    end

    let(:benefits_intake_uuid) { SecureRandom.uuid }

    before do
      create(
        :form_submission_attempt,
        :vbms,
        form_submission:,
        benefits_intake_uuid:
      )
    end

    it 'enqueues an expiration Notification::Email' do
      expect(SimpleFormsApi::Notification::Email).to receive(:new).with(
        hash_including(
          form_number: 'vba_40_1330m',
          confirmation_number: benefits_intake_uuid
        ),
        notification_type: :expiration,
        user_account: anything
      ).and_return(notification_email)

      run_task
    end

    it 'marks the submission as emailed by setting expiration_email_sent_at' do
      allow(SimpleFormsApi::Notification::Email).to receive(:new).and_return(notification_email)
      allow(notification_email).to receive(:send).and_return('email_job_id')

      expect { run_task }.to change { form_submission.reload.expiration_email_sent_at }.from(nil)
    end
  end

  context 'when the flipper is disabled' do
    before do
      allow(Flipper).to receive(:enabled?).with(:form40_1330m_expiration_email).and_return(false)
    end

    it 'does not enqueue an email' do
      submission = create(
        :form_submission,
        form_type: '40-1330M',
        created_at: 31.days.ago,
        expiration_email_sent_at: nil,
        form_data: { 'applicantEmail' => 'applicant@example.com' }.to_json
      )
      create(
        :form_submission_attempt,
        :vbms,
        form_submission: submission,
        benefits_intake_uuid: SecureRandom.uuid
      )

      allow(SimpleFormsApi::Notification::Email).to receive(:new).and_return(notification_email)
      allow(notification_email).to receive(:send).and_return(nil)

      expect { run_task }.not_to raise_error
      expect(submission.reload.expiration_email_sent_at).to be_nil
    end
  end

  context 'when the template id is not configured' do
    before do
      allow(Settings.vanotify.services.va_gov.template_id).to receive(:[])
        .with('form40_1330m_expiration_email')
        .and_return(nil)
    end

    it 'does not enqueue an email' do
      submission = create(
        :form_submission,
        form_type: '40-1330M',
        created_at: 31.days.ago,
        expiration_email_sent_at: nil,
        form_data: { 'applicantEmail' => 'applicant@example.com' }.to_json
      )
      create(
        :form_submission_attempt,
        :vbms,
        form_submission: submission,
        benefits_intake_uuid: SecureRandom.uuid
      )

      allow(SimpleFormsApi::Notification::Email).to receive(:new).and_return(notification_email)
      allow(notification_email).to receive(:send).and_return(nil)

      expect { run_task }.not_to raise_error
      expect(submission.reload.expiration_email_sent_at).to be_nil
    end
  end

  context 'when the submission has already been emailed (expiration_email_sent_at is set)' do
    it 'does not enqueue another email' do
      submission = create(
        :form_submission,
        form_type: '40-1330M',
        created_at: 31.days.ago,
        expiration_email_sent_at: 1.day.ago,
        form_data: { 'applicantEmail' => 'applicant@example.com' }.to_json
      )
      create(
        :form_submission_attempt,
        :vbms,
        form_submission: submission,
        benefits_intake_uuid: SecureRandom.uuid
      )

      expect(SimpleFormsApi::Notification::Email).not_to receive(:new)
      run_task
    end
  end

  context 'when the submission was created within the last 30 days (not yet expired)' do
    it 'does not enqueue an email' do
      recent_submission = create(
        :form_submission,
        form_type: '40-1330M',
        created_at: 5.days.ago,
        expiration_email_sent_at: nil,
        form_data: { 'applicantEmail' => 'recent@applicant.com' }.to_json
      )
      create(
        :form_submission_attempt,
        :vbms,
        form_submission: recent_submission,
        benefits_intake_uuid: SecureRandom.uuid
      )

      expect(SimpleFormsApi::Notification::Email).not_to receive(:new)
      run_task
    end
  end

  context 'when the submission is a different form type' do
    it 'does not enqueue an email' do
      other_submission = create(
        :form_submission,
        form_type: '21-4142',
        created_at: 31.days.ago,
        expiration_email_sent_at: nil,
        form_data: { 'applicantEmail' => 'other@applicant.com' }.to_json
      )
      create(
        :form_submission_attempt,
        :vbms,
        form_submission: other_submission,
        benefits_intake_uuid: SecureRandom.uuid
      )

      expect(SimpleFormsApi::Notification::Email).not_to receive(:new)
      run_task
    end
  end

  context 'when all attempts are still pending' do
    it 'does not enqueue an email (pending submissions are not eligible)' do
      submission = create(
        :form_submission,
        form_type: '40-1330M',
        created_at: 31.days.ago,
        expiration_email_sent_at: nil,
        form_data: { 'applicantEmail' => 'pending@applicant.com' }.to_json
      )
      create(:form_submission_attempt, :pending, form_submission: submission)

      expect(SimpleFormsApi::Notification::Email).not_to receive(:new)
      run_task
    end
  end

  context 'when enqueuing raises an error' do
    it 'logs the error and does not mark the submission as sent' do
      submission = create(
        :form_submission,
        form_type: '40-1330M',
        created_at: 31.days.ago,
        expiration_email_sent_at: nil,
        form_data: { 'applicantEmail' => 'applicant@example.com' }.to_json
      )
      create(
        :form_submission_attempt,
        :vbms,
        form_submission: submission,
        benefits_intake_uuid: SecureRandom.uuid
      )

      allow(SimpleFormsApi::Notification::Email).to receive(:new).and_raise(StandardError, 'VANotify down')
      allow(Rails.logger).to receive(:error)

      expect { run_task }.not_to raise_error
      expect(submission.reload.expiration_email_sent_at).to be_nil

      expect(Rails.logger).to have_received(:error).with(
        'SendExpirationEmails: Error enqueuing expiration email',
        form_submission_id: submission.id,
        message: 'VANotify down'
      )
    end
  end
end
