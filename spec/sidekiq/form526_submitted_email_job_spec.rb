# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Form526SubmittedEmailJob, type: :job do
  subject { described_class }

  let(:email_service) { instance_double(VaNotify::Service) }
  let!(:form526_submission) { create(:form526_submission, submitted_claim_id: 600_191_990) }

  before do
    Sidekiq::Job.clear_all
    allow(VaNotify::Service).to receive(:new).with(Settings.vanotify.services.va_gov.api_key).and_return(email_service)
    allow(Flipper).to receive(:enabled?).with(:form526_raise_e).and_return(false)
    allow(Flipper).to receive(:enabled?).with(:form526_error_handling).and_return(true)
  end

  describe '#perform' do
    let(:expected_params) do
      {
        email_address: 'test@email.com',
        template_id: Settings.vanotify.services.va_gov.template_id.form526_submitted_email,
        personalisation: {
          'claim_id' => 600_191_990,
          'date_submitted' => form526_submission.format_creation_time_for_mailers,
          'first_name' => form526_submission.get_first_name
        }
      }
    end

    it 'sends a submitted email using submission data' do
      expect(email_service).to receive(:send_email).with(expected_params)

      subject.new.perform(form526_submission.id)
    end

    it 'enqueues with submission id only' do
      subject.perform_async(form526_submission.id)

      expect(subject.jobs.last['args']).to eq([form526_submission.id])
    end

    it 'increments the success metric' do
      allow(email_service).to receive(:send_email)

      expect { subject.new.perform(form526_submission.id) }
        .to trigger_statsd_increment(described_class::STATSD_SUCCESS_NAME)
    end
  end
end
