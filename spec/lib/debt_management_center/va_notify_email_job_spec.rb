# frozen_string_literal: true

require 'rails_helper'
require 'sidekiq/testing'
require 'debt_management_center/sidekiq/va_notify_email_job'

RSpec.describe DebtManagementCenter::VANotifyEmailJob, type: :worker do
  let(:template_id) { 'template-123' }
  let(:va_notify_client) { instance_double(VaNotify::Service) }
  let(:email_options) { { 'id_type' => 'email' } }
  let(:lockbox) { Lockbox.new(key: Settings.lockbox.master_key, encode: true) }

  before do
    allow(VaNotify::Service).to receive(:new).and_return(va_notify_client)
    allow(va_notify_client).to receive(:send_email)
    allow(Sidekiq::AttrPackage).to receive(:delete)
  end

  def perform_job(identifier:, personalisation:, **options)
    described_class.new.perform(identifier, template_id, personalisation, email_options.merge(options))
  end

  describe 'Lockbox decryption' do
    it 'decrypts identifier and personalisation names with Lockbox before sending to VaNotify' do
      first_name = 'Jane'
      encrypted_email = lockbox.encrypt('veteran@va.gov')
      encrypted_first_name = lockbox.encrypt(first_name)
      encrypted_name = lockbox.encrypt(first_name)

      expect(va_notify_client).to receive(:send_email).with(
        hash_including(
          email_address: 'veteran@va.gov',
          template_id:,
          personalisation: hash_including('first_name' => first_name, 'name' => first_name)
        )
      )
      perform_job(
        identifier: encrypted_email,
        personalisation: {
          'first_name' => encrypted_first_name,
          'name' => encrypted_name,
          'date_submitted' => '01/15/2025'
        }
      )
    end

    it 'uses plain identifier and first_name as-is when Lockbox.decrypt raises InvalidMessage' do
      expect(va_notify_client).to receive(:send_email).with(
        hash_including(
          email_address: 'plain@example.com',
          personalisation: hash_including('first_name' => 'PlainName')
        )
      )
      perform_job(identifier: 'plain@example.com', personalisation: { 'first_name' => 'PlainName' })
    end
  end

  describe '#perform' do
    describe 'PII never logged' do
      it 'does not log email or first_name when retries exhausted' do
        pii_email = 'pii-no-log@example.com'
        pii_first_name = 'NoLogFirst'
        log_calls = []
        allow(Rails.logger).to receive(:error) { |*args|
          log_calls << args.map(&:to_s).join(' ')
          nil
        }
        allow(StatsD).to receive(:increment)
        exception = StandardError.new('fail')
        allow(exception).to receive(:backtrace).and_return([])

        job = { 'args' => [pii_email, 'template_id', { 'first_name' => pii_first_name }, {}] }
        described_class.sidekiq_retries_exhausted_block.call(job, exception)

        logged = log_calls.join(' ')
        expect(logged).not_to include(pii_email), 'email must not appear in any log'
        expect(logged).not_to include(pii_first_name), 'first_name must not appear in any log'
      end
    end

    it 'sends direct email params to VaNotify' do
      expect(va_notify_client).to receive(:send_email).with(
        hash_including(
          email_address: 'user@example.com',
          template_id:,
          personalisation: hash_including('first_name' => 'Test')
        )
      )
      perform_job(identifier: 'user@example.com', personalisation: { 'first_name' => 'Test' })
    end

    context 'when cache_key is not provided' do
      it 'does not read from AttrPackage' do
        expect(Sidekiq::AttrPackage).not_to receive(:find)
        perform_job(identifier: 'user@example.com', personalisation: { 'first_name' => 'Test' })
      end
    end

    context 'when cache_key is provided' do
      let(:cache_key) { 'cache_key_abc' }
      let(:cache_options) { email_options.merge('cache_key' => cache_key) }

      it 'sends cached email params to VaNotify' do
        allow(Sidekiq::AttrPackage).to receive(:find).with(cache_key).and_return(
          email: 'cached@example.com',
          personalisation: { 'first_name' => 'CachedFirst', 'date_submitted' => '01/01/2025' }
        )

        expect(va_notify_client).to receive(:send_email).with(
          hash_including(
            email_address: 'cached@example.com',
            template_id:,
            personalisation: hash_including('first_name' => 'CachedFirst')
          )
        )
        described_class.new.perform(nil, template_id, nil, cache_options)
      end

      it 'deletes the cache key after sending email' do
        allow(Sidekiq::AttrPackage).to receive(:find).with(cache_key).and_return(
          email: 'cached@example.com',
          personalisation: {}
        )

        expect(Sidekiq::AttrPackage).to receive(:delete).with(cache_key)
        described_class.new.perform(nil, template_id, nil, cache_options)
      end

      it 'raises an argument error when the cached attributes are missing' do
        allow(Sidekiq::AttrPackage).to receive(:find).with(cache_key).and_return(nil)

        expect { described_class.new.perform(nil, template_id, nil, cache_options) }
          .to raise_error(ArgumentError, /AttrPackage.*error/)
      end
    end
  end

  describe 'sidekiq_retries_exhausted' do
    subject(:config) { described_class }

    let(:exception) do
      e = StandardError.new('oh shoot')
      allow(e).to receive(:backtrace).and_return(['line 1', 'line 2', 'line 3'])
      e
    end
    let(:exhausted_job) { { 'args' => [nil, nil, nil, {}] } }

    it 'logs the error with exception details' do
      expect(StatsD).to receive(:increment).with(
        "#{DebtManagementCenter::VANotifyEmailJob::STATS_KEY}.retries_exhausted"
      )
      expect(StatsD).not_to receive(:increment).with(
        "#{DebtsApi::V0::Form5655Submission::STATS_KEY}.send_failed_form_email.failure"
      )
      expect(Rails.logger).to receive(:error).with('VANotifyEmailJob retries exhausted', hash_including(exception:))
      config.sidekiq_retries_exhausted_block.call(exhausted_job, exception)
    end

    it 'deletes cache_key when retries expire' do
      cache_key = 'test_cache_key_123'
      job = { 'args' => [nil, nil, nil, { 'cache_key' => cache_key }] }

      expect(Sidekiq::AttrPackage).to receive(:delete).with(cache_key)
      allow(StatsD).to receive(:increment)
      allow(Rails.logger).to receive(:error)
      config.sidekiq_retries_exhausted_block.call(job, exception)
    end

    context 'when firing a silent error email' do
      let(:email) { 'test@tester.com' }
      let(:template_id) { DebtsApi::V0::Form5655Submission::SUBMISSION_FAILURE_EMAIL_TEMPLATE_ID }
      let(:job_args) { [email, template_id, nil, { 'failure_mailer' => true }] }
      let(:callback_options) { described_class::VA_NOTIFY_CALLBACK_OPTIONS }
      let(:personalisation) do
        {
          'first_name' => 'Homer',
          'date_submitted' => Time.zone.now.strftime('%m/%d/%Y'),
          'updated_at' => Time.zone.now.strftime('%m/%d/%Y'),
          'confirmation_number' => 'e7b5d0e3-2a6f-4b5b-91a5-0cc3d801f1e1'
        }
      end

      it 'increments the failure counter' do
        expect(StatsD).to receive(:increment).with(
          'silent_failure', tags: %w[service:debt-resolution function:sidekiq_retries_exhausted]
        )
        expect(StatsD).to receive(:increment).with('api.dmc.va_notify_email.retries_exhausted')
        expect(StatsD).to receive(:increment).with(
          "#{DebtsApi::V0::Form5655Submission::STATS_KEY}.send_failed_form_email.failure"
        )
        described_class.sidekiq_retries_exhausted_block.call({ 'args' => job_args }, exception)
      end

      it 'uses the callback options when failure_mailer is true' do
        allow(va_notify_client).to receive(:send_email)
        expect(VaNotify::Service).to receive(:new).with(
          Settings.vanotify.services.dmc.api_key,
          callback_options
        ).and_return(va_notify_client)
        config.new.perform(email, template_id, personalisation, { 'id_type' => 'email', 'failure_mailer' => true })
      end

      it 'does not use the callback options when failure_mailer is not set' do
        allow(va_notify_client).to receive(:send_email)
        expect(VaNotify::Service).to receive(:new).with(Settings.vanotify.services.dmc.api_key)
                                                  .and_return(va_notify_client)
        config.new.perform(email, template_id, personalisation)
      end
    end
  end
end
