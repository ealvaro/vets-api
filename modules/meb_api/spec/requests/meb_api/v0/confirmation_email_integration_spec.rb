# frozen_string_literal: true

require 'rails_helper'
require 'sidekiq/testing'

RSpec.describe 'MEB API Confirmation Email Integration', type: :request do
  let(:user) { build(:user, :loa3, email: 'user@example.com', icn: '1234567890V123456') }
  let(:user_no_email) { build(:user, :loa3, email: nil, icn: '9876543210V654321') }
  let(:params) { { claim_status: 'ELIGIBLE', email: 'test@example.com', first_name: 'John' } }

  before do
    Sidekiq::Testing.fake!
    sign_in_as(user)
    allow(Rails.logger).to receive(:info)
    allow(Rails.logger).to receive(:warn)
    allow(StatsD).to receive(:increment)
  end

  after { Sidekiq::Worker.clear_all }

  shared_examples 'confirmation email endpoint' do |form_tag, url, flipper_key, worker_class, extra_params = {}|
    it 'dispatches worker and logs when enabled' do
      allow(Flipper).to receive(:enabled?).with(flipper_key).and_return(true)

      expect { post url, params: params.merge(extra_params) }.to change(worker_class.jobs, :size).by(1)
      expect(Rails.logger).to have_received(:info).with(
        'MEB confirmation email endpoint called',
        hash_including(form_tag:)
      )
      expect(StatsD).to have_received(:increment).with(
        'api.meb.confirmation_email.dispatched',
        tags: [form_tag, 'claim_status:ELIGIBLE']
      )
    end

    it 'skips and logs when flipper disabled' do
      allow(Flipper).to receive(:enabled?).with(flipper_key).and_return(false)

      expect { post url, params: params.merge(extra_params) }.not_to change(worker_class.jobs, :size)
      expect(Rails.logger).to have_received(:warn).with(
        'MEB confirmation email skipped',
        hash_including(form_tag:, reason: 'flipper_disabled')
      )
    end

    it 'skips and logs when email missing' do
      allow(Flipper).to receive(:enabled?).with(flipper_key).and_return(true)

      sign_in_as(user_no_email)
      params_without_email = { claim_status: 'ELIGIBLE', first_name: 'John' }.merge(extra_params)

      expect { post url, params: params_without_email }.not_to change(worker_class.jobs, :size)
      expect(Rails.logger).to have_received(:warn).with(
        'MEB confirmation email skipped',
        hash_including(form_tag:, reason: 'email_missing')
      )
      expect(StatsD).to have_received(:increment).with(
        'api.meb.confirmation_email.skipped',
        tags: [form_tag, 'reason:email_missing']
      )
    end
  end

  describe 'POST /meb_api/v0/forms_send_confirmation_email' do
    include_examples 'confirmation email endpoint',
                     'form:1990emeb',
                     '/meb_api/v0/forms_send_confirmation_email',
                     :form1990emeb_confirmation_email,
                     MebApi::V0::Submit1990emebFormConfirmation
  end

  describe 'POST /meb_api/v0/send_confirmation_email' do
    include_examples 'confirmation email endpoint',
                     'form:1990meb',
                     '/meb_api/v0/send_confirmation_email',
                     :form1990meb_confirmation_email,
                     MebApi::V0::Submit1990mebFormConfirmation
  end

  describe 'POST /meb_api/v0/forms_send_confirmation_email (10297)' do
    include_examples 'confirmation email endpoint',
                     'form:10297',
                     '/meb_api/v0/forms_send_confirmation_email',
                     :form10297_meb_confirmation_email,
                     MebApi::V0::Submit10297FormConfirmation,
                     { form_type: '10297' }
  end

  describe 'POST /meb_api/v0/send_confirmation_email (Chapter 1606)' do
    before do
      allow(Flipper).to receive(:enabled?).with(:meb_1606_30_confirmation_pages).and_return(true)
    end

    include_examples 'confirmation email endpoint',
                     'form:1990_chapter1606',
                     '/meb_api/v0/send_confirmation_email',
                     :form1990meb_confirmation_email,
                     MebApi::V0::Submit1606FormConfirmation,
                     { chapter_type: 'chapter1606' }
  end

  describe 'POST /meb_api/v0/send_confirmation_email (Chapter 30)' do
    before do
      allow(Flipper).to receive(:enabled?).with(:meb_1606_30_confirmation_pages).and_return(true)
    end

    include_examples 'confirmation email endpoint',
                     'form:1990_chapter30',
                     '/meb_api/v0/send_confirmation_email',
                     :form1990meb_confirmation_email,
                     MebApi::V0::Submit30FormConfirmation,
                     { chapter_type: 'chapter30' }
  end
end
