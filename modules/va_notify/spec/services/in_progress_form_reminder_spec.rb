# frozen_string_literal: true

require 'rails_helper'
require 'sidekiq/testing'

describe VANotify::InProgressFormReminder, type: :worker do
  let(:user) { create(:user) }
  let(:in_progress_form) do
    create(:in_progress_686c_form, user_uuid: user.uuid, user_account: create(:user_account))
  end

  describe '#perform' do
    it 'returns early if the in_progress_form is not found' do
      allow(InProgressForm).to receive(:find_by).and_return(nil)
      allow(VANotify::Veteran).to receive(:new)
      allow(VANotify::V2::QueueUserAccountJob).to receive(:enqueue)

      result = Sidekiq::Testing.inline! do
        described_class.new.perform(in_progress_form.id)
      end

      expect(result).to be_nil
      expect(VANotify::Veteran).not_to have_received(:new)
      expect(VANotify::V2::QueueUserAccountJob).not_to have_received(:enqueue)
    end

    it 'skips sending reminder email if there is no first name' do
      veteran_double = double('VaNotify::Veteran')
      allow(veteran_double).to receive_messages(icn: 'icn', first_name: nil)
      allow(VANotify::Veteran).to receive(:new).and_return(veteran_double)

      allow(VANotify::V2::QueueUserAccountJob).to receive(:enqueue)

      Sidekiq::Testing.inline! do
        described_class.new.perform(in_progress_form.id)
      end

      expect(VANotify::V2::QueueUserAccountJob).not_to have_received(:enqueue)
    end

    it 'rescues VANotify::Veteran::MPIError and returns nil' do
      allow(VANotify::V2::QueueUserAccountJob).to receive(:enqueue)
      allow(VANotify::Veteran).to receive(:new).and_raise(VANotify::Veteran::MPIError)

      result = Sidekiq::Testing.inline! do
        described_class.new.perform(in_progress_form.id)
      end

      expect(result).to be_nil
      expect(VANotify::V2::QueueUserAccountJob).not_to have_received(:enqueue)
    end

    it 'rescues VANotify::Veteran::MPINameError and returns nil' do
      allow(VANotify::V2::QueueUserAccountJob).to receive(:enqueue)
      allow(VANotify::Veteran).to receive(:new).and_raise(VANotify::Veteran::MPINameError)

      result = Sidekiq::Testing.inline! do
        described_class.new.perform(in_progress_form.id)
      end

      expect(result).to be_nil
      expect(VANotify::V2::QueueUserAccountJob).not_to have_received(:enqueue)
    end

    describe 'single relevant in_progress_form' do
      let(:user_with_icn) { double('VANotify::Veteran', icn: 'icn', first_name: 'first_name', uuid: 'uuid') }

      before do
        allow(VANotify::Veteran).to receive(:new).and_return(user_with_icn)
        allow(VANotify::V2::QueueUserAccountJob).to receive(:enqueue)
      end

      it 'delegates to VANotify::V2::QueueUserAccountJob' do
        expiration_date = in_progress_form.expires_at.strftime('%B %d, %Y')

        Sidekiq::Testing.inline! do
          described_class.new.perform(in_progress_form.id)
        end

        expect(VANotify::V2::QueueUserAccountJob).to have_received(:enqueue)
          .with(in_progress_form.user_account_id, 'fake_template_id',
                {
                  'first_name' => 'FIRST_NAME',
                  'date' => expiration_date,
                  'form_age' => ''
                },
                'Settings.vanotify.services.va_gov.api_key',
                { callback_metadata: {
                  form_number: '686C-674', notification_type: 'in_progress_reminder', statsd_tags: {
                    'function' => '686C-674 in progress reminder', 'service' => 'va-notify'
                  }
                } })
      end

      context 'with a 686+674 V2 form' do
        let(:in_progress_form) do
          create(:in_progress_686c_674_form, user_uuid: user.uuid, user_account: create(:user_account))
        end

        it 'uses the correct template id' do
          expiration_date = in_progress_form.expires_at.strftime('%B %d, %Y')

          Sidekiq::Testing.inline! do
            described_class.new.perform(in_progress_form.id)
          end

          expect(VANotify::V2::QueueUserAccountJob).to have_received(:enqueue)
            .with(in_progress_form.user_account_id, 'fake_template_686_674_id',
                  {
                    'first_name' => 'FIRST_NAME',
                    'date' => expiration_date,
                    'form_age' => ''
                  },
                  'Settings.vanotify.services.va_gov.api_key',
                  { callback_metadata: {
                    form_number: '686C-674-V2', notification_type: 'in_progress_reminder', statsd_tags: {
                      'function' => '686C-674-V2 in progress reminder', 'service' => 'va-notify'
                    }
                  } })
        end
      end

      context 'with a 686-only form' do
        let(:in_progress_form) do
          create(:in_progress_686_only_form, user_uuid: user.uuid, user_account: create(:user_account))
        end

        it 'uses the correct template id' do
          expiration_date = in_progress_form.expires_at.strftime('%B %d, %Y')

          Sidekiq::Testing.inline! do
            described_class.new.perform(in_progress_form.id)
          end

          expect(VANotify::V2::QueueUserAccountJob).to have_received(:enqueue)
            .with(in_progress_form.user_account_id, 'fake_template_686_only_id',
                  {
                    'first_name' => 'FIRST_NAME',
                    'date' => expiration_date,
                    'form_age' => ''
                  },
                  'Settings.vanotify.services.va_gov.api_key',
                  { callback_metadata: {
                    form_number: '686C-674-V2', notification_type: 'in_progress_reminder', statsd_tags: {
                      'function' => '686C-674-V2 in progress reminder', 'service' => 'va-notify'
                    }
                  } })
        end
      end

      context 'with a 674-only form' do
        let(:in_progress_form) do
          create(:in_progress_674_only_form, user_uuid: user.uuid, user_account: create(:user_account))
        end

        it 'uses the correct template id' do
          expiration_date = in_progress_form.expires_at.strftime('%B %d, %Y')

          Sidekiq::Testing.inline! do
            described_class.new.perform(in_progress_form.id)
          end

          expect(VANotify::V2::QueueUserAccountJob).to have_received(:enqueue)
            .with(in_progress_form.user_account_id, 'fake_template_674_only_id',
                  {
                    'first_name' => 'FIRST_NAME',
                    'date' => expiration_date,
                    'form_age' => ''
                  },
                  'Settings.vanotify.services.va_gov.api_key',
                  { callback_metadata: {
                    form_number: '686C-674-V2', notification_type: 'in_progress_reminder', statsd_tags: {
                      'function' => '686C-674-V2 in progress reminder', 'service' => 'va-notify'
                    }
                  } })
        end
      end
    end

    describe 'generic template fallback logging (686C-674-V2)' do
      let(:user_with_icn) { double('VANotify::Veteran', icn: 'icn', first_name: 'first_name', uuid: 'uuid') }
      let(:log_message) do
        'VANotify::InProgressFormReminder#find_template_id'
      end

      before do
        allow(VANotify::Veteran).to receive(:new).and_return(user_with_icn)
        allow(VANotify::V2::QueueUserAccountJob).to receive(:enqueue)
        allow(Rails.logger).to receive(:warn)
      end

      context 'when the 686 and 674 predicates both return false' do
        let(:in_progress_form) do
          create(:in_progress_form,
                 form_id: '686C-674-V2',
                 user_uuid: user.uuid,
                 user_account: create(:user_account),
                 form_data: { 'view:selectable686_options' => {} }.to_json)
        end

        it 'logs the fallback with reason predicates_returned_false and no error' do
          Sidekiq::Testing.inline! do
            described_class.new.perform(in_progress_form.id)
          end

          expect(Rails.logger).to have_received(:warn).with(
            log_message,
            hash_including(
              in_progress_form_id: in_progress_form.id,
              form_id: '686C-674-V2',
              reason: 'predicates_returned_false',
              error_class: nil
            )
          )
          expect(VANotify::V2::QueueUserAccountJob).not_to have_received(:enqueue)
        end
      end

      context 'when a predicate raises because the options are not at the top level' do
        let(:in_progress_form) do
          create(:in_progress_form,
                 form_id: '686C-674-V2',
                 user_uuid: user.uuid,
                 user_account: create(:user_account),
                 form_data: {
                   'dependents_application' => { 'view:selectable686_options' => { 'add_spouse' => true } }
                 }.to_json)
        end

        it 'logs the fallback with reason exception_raised and the error class' do
          Sidekiq::Testing.inline! do
            described_class.new.perform(in_progress_form.id)
          end

          expect(Rails.logger).to have_received(:warn).with(
            log_message,
            hash_including(
              in_progress_form_id: in_progress_form.id,
              form_id: '686C-674-V2',
              reason: 'exception_raised',
              error_class: 'NoMethodError'
            )
          )
          expect(VANotify::V2::QueueUserAccountJob).not_to have_received(:enqueue)
        end
      end

      context 'when the form resolves to a specific template' do
        let(:in_progress_form) do
          create(:in_progress_686c_674_form, user_uuid: user.uuid, user_account: create(:user_account))
        end

        it 'does not log a generic fallback' do
          Sidekiq::Testing.inline! do
            described_class.new.perform(in_progress_form.id)
          end

          expect(Rails.logger).not_to have_received(:warn).with(log_message, anything)
        end
      end
    end

    describe 'multiple relevant in_progress_forms' do
      let!(:in_progress_form_1) do
        Timecop.freeze(7.days.ago)
        in_progress_form = create(
          :in_progress_686c_form,
          user_uuid: user.uuid,
          user_account: create(:user_account)
        )
        Timecop.return
        in_progress_form
      end

      let!(:in_progress_form_2) do
        create_in_progress_form_days_ago(1, user_uuid: user.uuid, form_id: 'form_2_id')
      end

      let!(:in_progress_form_3) do
        create_in_progress_form_days_ago(2, user_uuid: user.uuid, form_id: 'form_3_id')
      end

      it 'skips email if its not the oldest in_progress_form' do
        veteran_double = double('VaNotify::Veteran')
        allow(veteran_double).to receive_messages(icn: 'icn', first_name: 'first_name')
        allow(VANotify::Veteran).to receive(:new).and_return(veteran_double)

        allow(VANotify::V2::QueueUserAccountJob).to receive(:enqueue)
        stub_const('VANotify::FindInProgressForms::RELEVANT_FORMS', %w[686C-674 form_2_id form_3_id])

        Sidekiq::Testing.inline! do
          described_class.new.perform(in_progress_form_3.id)
        end

        expect(VANotify::V2::QueueUserAccountJob).not_to have_received(:enqueue)
      end

      it 'delegates to VANotify::V2::QueueUserAccountJob if its the oldest in_progress_form' do
        user_with_icn = double('VANotify::Veteran', icn: 'icn', first_name: 'first_name', uuid: 'uuid')
        allow(VANotify::Veteran).to receive(:new).and_return(user_with_icn)

        allow(VANotify::V2::QueueUserAccountJob).to receive(:enqueue)
        stub_const('VANotify::FindInProgressForms::RELEVANT_FORMS', %w[686C-674 form_2_id form_3_id])
        stub_const(
          'VANotify::InProgressFormHelper::FRIENDLY_FORM_SUMMARY',
          {
            '686C-674' => '686c something',
            'form_2_id' => 'form_2 something',
            'form_3_id' => 'form_3 something'
          }
        )

        stub_const(
          'VANotify::InProgressFormHelper::FRIENDLY_FORM_ID',
          {
            '686C-674' => '686C-674',
            'form_2_id' => 'form_2_example_id',
            'form_3_id' => 'form_3_example_id'
          }
        )

        form_1_date = in_progress_form_1.expires_at.strftime('%B %d, %Y')
        form_2_date = in_progress_form_2.expires_at.strftime('%B %d, %Y')
        form_3_date = in_progress_form_3.expires_at.strftime('%B %d, %Y')

        Sidekiq::Testing.inline! do
          described_class.new.perform(in_progress_form_1.id)
        end

        # rubocop:disable Layout/LineLength
        expect(VANotify::V2::QueueUserAccountJob).to have_received(:enqueue).with(
          in_progress_form_1.user_account_id,
          'fake_template_id',
          {
            'first_name' => 'FIRST_NAME',
            'formatted_form_data' => "\n^ FORM 686C-674\n^\n^__686c something__\n^\n^_Application expires on:_ #{form_1_date}\n\n\n^---\n\n^ FORM form_3_example_id\n^\n^__form_3 something__\n^\n^_Application expires on:_ #{form_3_date}\n\n\n^---\n\n^ FORM form_2_example_id\n^\n^__form_2 something__\n^\n^_Application expires on:_ #{form_2_date}\n\n"
          },
          'Settings.vanotify.services.va_gov.api_key',
          { callback_metadata: {
            form_number: 'multiple', notification_type: 'in_progress_reminder', statsd_tags: {
              'function' => 'multiple in progress reminder', 'service' => 'va-notify'
            }
          } }
        )
        # rubocop:enable Layout/LineLength
      end
    end
  end

  def create_in_progress_form_days_ago(count, user_uuid:, form_id:)
    Timecop.freeze(count.days.ago)
    in_progress_form = create(:in_progress_form, user_uuid:, form_id:)
    Timecop.return
    in_progress_form
  end
end
