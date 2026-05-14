# frozen_string_literal: true

require 'rails_helper'
require 'vha_notification/service'

RSpec.describe VHANotification::SendMstConsentJob, type: :job do
  subject(:perform_job) { described_class.new.perform(submission.id, submission_path) }

  let(:submission_path) { 'primary' }
  let(:submission) { create(:form526_submission, :with_0781v2) }
  let(:service) { instance_double(VHANotification::Service) }

  before do
    allow(StatsD).to receive(:increment)
    allow(Rails.logger).to receive(:info)
    allow(Rails.logger).to receive(:error)
    allow(VHANotification::Service).to receive(:new).and_return(service)
    allow(service).to receive(:send_mst_consent).and_return({ success: true })
  end

  context 'when optionIndicator is notEnrolled' do
    before do
      form_data = submission.form
      form_data['form0781']['form0781v2']['optionIndicator'] = 'notEnrolled'
      submission.update!(form_json: form_data.to_json)
      submission.invalidate_form_hash
    end

    it 'skips without calling the service' do
      perform_job

      expect(service).not_to have_received(:send_mst_consent)
      expect(StatsD).to have_received(:increment)
        .with("#{described_class::STATSD_KEY_PREFIX}.skipped", tags: ['reason:not_enrolled', 'path:primary'])
      expect(StatsD).not_to have_received(:increment).with("#{described_class::STATSD_KEY_PREFIX}.success")
      expect(Rails.logger).not_to have_received(:info).with('VHA Notification MST consent job succeeded', anything)
    end
  end

  context 'when optionIndicator is blank' do
    before do
      form_data = submission.form
      form_data['form0781']['form0781v2']['optionIndicator'] = nil
      submission.update!(form_json: form_data.to_json)
      submission.invalidate_form_hash
    end

    it 'skips with no_consent without calling the service' do
      perform_job

      expect(service).not_to have_received(:send_mst_consent)
      expect(StatsD).to have_received(:increment)
        .with("#{described_class::STATSD_KEY_PREFIX}.skipped", tags: ['reason:no_consent', 'path:primary'])
      expect(StatsD).not_to have_received(:increment).with("#{described_class::STATSD_KEY_PREFIX}.success")
      expect(Rails.logger).not_to have_received(:info).with('VHA Notification MST consent job succeeded', anything)
    end
  end

  context 'when optionIndicator is yes' do
    before do
      form_data = submission.form
      form_data['form0781']['form0781v2']['optionIndicator'] = 'yes'
      submission.update!(form_json: form_data.to_json)
      submission.invalidate_form_hash
    end

    it 'calls the service with participant id and true consent' do
      allow(service).to receive(:send_mst_consent).and_return({ success: true })

      perform_job

      expect(service).to have_received(:send_mst_consent).with(submission.auth_headers['va_eauth_pid'].to_s, true)
      expect(StatsD).to have_received(:increment).with("#{described_class::STATSD_KEY_PREFIX}.success")
      expect(StatsD).to have_received(:increment).with("#{described_class::STATSD_KEY_PREFIX}.total")
    end

    it 'increments failure and raises when service call fails' do
      allow(service).to receive(:send_mst_consent).and_raise(VHANotification::ServiceError, 'boom')

      expect { perform_job }.to raise_error(VHANotification::ServiceError, 'boom')
      expect(StatsD).to have_received(:increment).with("#{described_class::STATSD_KEY_PREFIX}.failure")
      expect(StatsD).to have_received(:increment).with("#{described_class::STATSD_KEY_PREFIX}.total")
    end

    it 'skips when participant id is blank' do
      auth_headers = submission.auth_headers
      auth_headers['va_eauth_pid'] = '   '
      submission.update!(auth_headers_json: auth_headers.to_json)

      perform_job

      expect(service).not_to have_received(:send_mst_consent)
      expect(StatsD).to have_received(:increment)
        .with("#{described_class::STATSD_KEY_PREFIX}.skipped", tags: ['reason:missing_participant_id',
                                                                      'path:primary'])
      expect(StatsD).to have_received(:increment).with("#{described_class::STATSD_KEY_PREFIX}.total")
      expect(StatsD).not_to have_received(:increment).with("#{described_class::STATSD_KEY_PREFIX}.success")
      expect(Rails.logger).not_to have_received(:info).with('VHA Notification MST consent job succeeded', anything)
    end
  end

  context 'when optionIndicator is no' do
    before do
      form_data = submission.form
      form_data['form0781']['form0781v2']['optionIndicator'] = 'no'
      submission.update!(form_json: form_data.to_json)
      submission.invalidate_form_hash
    end

    it 'calls the service with false consent' do
      allow(service).to receive(:send_mst_consent).and_return({ success: true })

      perform_job

      expect(service).to have_received(:send_mst_consent).with(submission.auth_headers['va_eauth_pid'].to_s, false)
    end
  end

  context 'when optionIndicator is revoke' do
    before do
      form_data = submission.form
      form_data['form0781']['form0781v2']['optionIndicator'] = 'revoke'
      submission.update!(form_json: form_data.to_json)
      submission.invalidate_form_hash
    end

    it 'calls the service with false consent' do
      allow(service).to receive(:send_mst_consent).and_return({ success: true })

      perform_job

      expect(service).to have_received(:send_mst_consent).with(submission.auth_headers['va_eauth_pid'].to_s, false)
    end
  end

  describe 'when retries are exhausted' do
    it 'increments exhausted metric and logs terminal failure' do
      msg = {
        'args' => [submission.id, 'primary'],
        'error_class' => 'VHANotification::ServiceError',
        'error_message' => 'boom'
      }

      described_class.within_sidekiq_retries_exhausted_block(msg) do
        expect(StatsD).to receive(:increment).with("#{described_class::STATSD_KEY_PREFIX}.exhausted")
        expect(Rails.logger).to receive(:error).with(
          'VHA Notification MST consent job retries exhausted',
          hash_including(
            form526_submission_id: submission.id,
            submission_path: 'primary',
            error_class: 'VHANotification::ServiceError',
            error_message: 'boom'
          )
        )
      end
    end
  end
end
