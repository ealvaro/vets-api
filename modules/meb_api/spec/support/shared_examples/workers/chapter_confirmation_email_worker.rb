# frozen_string_literal: true

RSpec.shared_examples 'a chapter confirmation email worker' do |
  form_type:,
  form_tag:,
  approved_template:,
  offramp_template:,
  worker_class:
|
  include ActiveSupport::Testing::TimeHelpers

  let(:email) { 'test@example.com' }
  let(:first_name) { 'TEST' }
  let(:user_icn) { '1234567890V123456' }
  let(:today) { Time.zone.today.strftime('%B %d, %Y') }
  let(:worker) { described_class.new }

  before do
    allow(VANotify::EmailJob).to receive(:perform_async)
    allow(Rails.logger).to receive(:info)
    allow(Rails.logger).to receive(:error)
    allow(StatsD).to receive(:increment)
  end

  shared_context 'with approved template' do
    before do
      template_double = double('template_id', approved_template => 'approved_template')
      allow(Settings.vanotify.services.va_gov).to receive(:template_id).and_return(template_double)
    end
  end

  shared_context 'with offramp template' do
    before do
      template_double = double('template_id', offramp_template => 'offramp_template')
      allow(Settings.vanotify.services.va_gov).to receive(:template_id).and_return(template_double)
    end
  end

  shared_context 'with v2 disabled' do
    before { allow(Flipper).to receive(:enabled?).with(:va_notify_v2_meb_confirmation_email).and_return(false) }
  end

  shared_context 'with v2 enabled' do
    before do
      allow(Flipper).to receive(:enabled?).with(:va_notify_v2_meb_confirmation_email).and_return(true)
      allow(VANotify::V2::QueueEmailJob).to receive(:enqueue)
    end
  end

  shared_examples 'sends via V1' do |template:, claim_status:, expected_date: nil|
    it 'sends email via V1 EmailJob' do
      worker.perform(claim_status, email, first_name, user_icn)

      expect(VANotify::EmailJob).to have_received(:perform_async).with(
        email,
        template,
        {
          'first_name' => first_name,
          'date_submitted' => expected_date || today
        }
      )
    end
  end

  shared_examples 'sends via V2' do |template:, claim_status:, expected_date: nil|
    it 'sends email via V2 QueueEmailJob' do
      worker.perform(claim_status, email, first_name, user_icn)

      expect(VANotify::V2::QueueEmailJob).to have_received(:enqueue).with(
        email,
        template,
        {
          'first_name' => first_name,
          'date_submitted' => expected_date || today
        },
        'Settings.vanotify.services.va_gov.api_key'
      )
      expect(VANotify::EmailJob).not_to have_received(:perform_async)
    end
  end

  describe 'constants' do
    it { expect(described_class::FORM_TYPE).to eq(form_type) }
    it { expect(described_class::FORM_TAG).to eq(form_tag) }
  end

  describe 'email delivery' do
    context 'when claim status is ELIGIBLE' do
      include_context 'with approved template'

      context 'with V2 disabled' do
        include_context 'with v2 disabled'

        it 'sends email with correct date' do
          travel_to Time.zone.local(2024, 1, 15) do
            worker.perform('ELIGIBLE', email, first_name, user_icn)

            expect(VANotify::EmailJob).to have_received(:perform_async).with(
              email,
              'approved_template',
              { 'first_name' => first_name, 'date_submitted' => Time.zone.today.strftime('%B %d, %Y') }
            )
          end
        end
      end

      context 'with V2 enabled' do
        include_context 'with v2 enabled'

        it 'sends via V2 and not V1' do
          travel_to Time.zone.local(2024, 1, 15) do
            worker.perform('ELIGIBLE', email, first_name, user_icn)

            expect(VANotify::V2::QueueEmailJob).to have_received(:enqueue)
            expect(VANotify::EmailJob).not_to have_received(:perform_async)
          end
        end
      end
    end

    context 'when claim status is not ELIGIBLE (offramp)' do
      include_context 'with offramp template'

      context 'with V2 disabled' do
        include_context 'with v2 disabled'
        include_examples 'sends via V1', template: 'offramp_template', claim_status: 'IN_PROGRESS'
      end

      context 'with V2 enabled' do
        include_context 'with v2 enabled'
        include_examples 'sends via V2', template: 'offramp_template', claim_status: 'IN_PROGRESS'
      end
    end

    context 'with various claim statuses' do
      include_context 'with offramp template'
      include_context 'with v2 disabled'

      %w[DENIED UNDER_REVIEW].each do |status|
        it "uses offramp template for #{status} status" do
          worker.perform(status, email, first_name, user_icn)

          expect(VANotify::EmailJob).to have_received(:perform_async).with(
            email,
            'offramp_template',
            hash_including('first_name' => first_name)
          )
        end
      end
    end
  end

  describe 'error handling' do
    let(:error) { VANotify::Error.new(500, 'Server error') }

    shared_examples 'logs and re-raises error' do
      it 'logs the error and re-raises for Sidekiq retry' do
        expect(Rails.logger).to receive(:error).with(
          'MEB confirmation email enqueue failed',
          hash_including(error_class: 'VANotify::Error')
        )

        expect { worker.perform('IN_PROGRESS', email, first_name, user_icn) }.to raise_error(VANotify::Error)
      end
    end

    context 'with V2 disabled' do
      before do
        allow(Flipper).to receive(:enabled?).with(:va_notify_v2_meb_confirmation_email).and_return(false)
        allow(VANotify::EmailJob).to receive(:perform_async).and_raise(error)
      end

      include_examples 'logs and re-raises error'
    end

    context 'with V2 enabled' do
      before do
        allow(Flipper).to receive(:enabled?).with(:va_notify_v2_meb_confirmation_email).and_return(true)
        allow(VANotify::V2::QueueEmailJob).to receive(:enqueue).and_raise(error)
      end

      include_examples 'logs and re-raises error'
    end
  end

  describe 'logging and metrics' do
    before do
      template_double = double(
        'template_id',
        approved_template => 'approved_template',
        offramp_template => 'offramp_template'
      )
      allow(Settings.vanotify.services.va_gov).to receive(:template_id).and_return(template_double)
      allow(Flipper).to receive(:enabled?).with(:va_notify_v2_meb_confirmation_email).and_return(false)
    end

    it 'logs attempt with correct details' do
      expect(Rails.logger).to receive(:info).with(
        'MEB confirmation email enqueue attempt',
        hash_including(form_type:, claim_status: 'ELIGIBLE', email_present: true)
      )

      worker.perform('ELIGIBLE', email, first_name, user_icn)
    end

    it 'logs success with correct details' do
      expect(Rails.logger).to receive(:info).with(
        'MEB confirmation email enqueued successfully',
        hash_including(form_type:, claim_status: 'ELIGIBLE')
      )

      worker.perform('ELIGIBLE', email, first_name, user_icn)
    end

    it 'increments enqueued metric with correct tags' do
      expect(StatsD).to receive(:increment).with(
        'api.meb.confirmation_email.enqueued',
        tags: [form_tag, 'claim_status:ELIGIBLE']
      )

      worker.perform('ELIGIBLE', email, first_name, user_icn)
    end

    it 'increments error metric with correct tags when error occurs' do
      allow(VANotify::EmailJob).to receive(:perform_async).and_raise(StandardError, 'Test error')

      expect(StatsD).to receive(:increment).with(
        'api.meb.confirmation_email.error',
        tags: array_including(
          'error_class:StandardError',
          form_tag,
          'claim_status:INPROGRESS',
          'template_id:offramp_template'
        )
      )

      expect { worker.perform('IN_PROGRESS', email, first_name, user_icn) }.to raise_error(StandardError)
    end
  end

  describe 'sidekiq_retries_exhausted callback' do
    let(:job) do
      {
        'class' => worker_class,
        'args' => ['ELIGIBLE', email, first_name, user_icn],
        'jid' => 'test_job_id'
      }
    end

    before do
      allow(Rails.logger).to receive(:error)
      allow(StatsD).to receive(:increment)
    end

    it 'logs retries exhausted with correct details' do
      expect(Rails.logger).to receive(:error).with(
        'MEB confirmation email retries exhausted',
        hash_including(
          form_type:,
          claim_status: 'ELIGIBLE',
          user_icn:,
          email_present: true,
          sidekiq_jid: 'test_job_id'
        )
      )

      described_class.sidekiq_retries_exhausted_block.call(job, StandardError.new('test'))
    end

    it 'increments retries exhausted metric with correct tags' do
      expect(StatsD).to receive(:increment).with(
        'api.meb.confirmation_email.retries_exhausted',
        tags: [form_tag, 'claim_status:ELIGIBLE']
      )

      described_class.sidekiq_retries_exhausted_block.call(job, StandardError.new('test'))
    end
  end
end
