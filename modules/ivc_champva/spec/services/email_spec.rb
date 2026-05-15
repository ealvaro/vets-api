# frozen_string_literal: true

require 'rails_helper'

RSpec.describe IvcChampva::Email, type: :service do
  subject { described_class.new(data) }

  let(:data) do
    {
      email: 'test@example.com',
      form_number: '10-10D',
      first_name: 'John',
      last_name: 'Doe',
      file_count: 3,
      pega_status: 'Processed',
      created_at: Time.zone.now.to_s,
      date_submitted: Time.zone.now.to_s,
      form_uuid: '4171e61a-03b5-49f3-8717-dbf340310473'
    }
  end

  let(:expected_template_id) { Settings.vanotify.services.ivc_champva.template_id.form_10_10d_email }
  let(:expected_personalisation) do
    %i[first_name last_name file_count pega_status date_submitted form_uuid].index_with { |k| data[k] }
  end
  let(:expected_callback_options) { { callback_klass: nil, callback_metadata: nil } }

  describe '#send_email' do
    before do
      allow(Rails).to receive(:env).and_return('staging')
    end

    context 'when va_notify_v2_ivc_champva_email flipper is disabled' do
      before do
        allow(Flipper).to receive(:enabled?).with(:va_notify_v2_ivc_champva_email).and_return(false)
      end

      it 'enqueues VANotify::EmailJob with correct parameters' do
        expect(VANotify::EmailJob).to receive(:perform_async).with(
          data[:email],
          expected_template_id,
          expected_personalisation,
          Settings.vanotify.services.ivc_champva.api_key,
          expected_callback_options
        )
        subject.send_email
      end

      it 'returns true on success' do
        allow(VANotify::EmailJob).to receive(:perform_async)
        expect(subject.send_email).to be true
      end
    end

    context 'when va_notify_v2_ivc_champva_email flipper is enabled' do
      before do
        allow(Flipper).to receive(:enabled?).with(:va_notify_v2_ivc_champva_email).and_return(true)
      end

      it 'enqueues VANotify::V2::QueueEmailJob with correct parameters' do
        expect(VANotify::V2::QueueEmailJob).to receive(:enqueue).with(
          data[:email],
          expected_template_id,
          expected_personalisation,
          'Settings.vanotify.services.ivc_champva.api_key',
          expected_callback_options
        )
        subject.send_email
      end

      it 'returns true on success' do
        allow(VANotify::V2::QueueEmailJob).to receive(:enqueue)
        expect(subject.send_email).to be true
      end

      context 'when an error occurs' do
        before do
          allow(VANotify::V2::QueueEmailJob).to receive(:enqueue).and_raise(StandardError.new('Test error'))
        end

        it 'handles the error and logs it' do
          allow(Rails.logger).to receive(:error)

          expect { subject.send_email }.not_to raise_error

          expect(Rails.logger).to have_received(:error).with('Pega Status Update Email Error: Test error')
        end
      end
    end

    context 'in invalid environments' do
      before do
        allow(Rails).to receive(:env).and_return('development')
      end

      it 'does not enqueue any email job' do
        expect(VANotify::EmailJob).not_to receive(:perform_async)
        expect(VANotify::V2::QueueEmailJob).not_to receive(:enqueue)
        subject.send_email
      end
    end

    context 'when an error occurs' do
      before do
        allow(Flipper).to receive(:enabled?).with(:va_notify_v2_ivc_champva_email).and_return(false)
        allow(VANotify::EmailJob).to receive(:perform_async).and_raise(StandardError.new('Test error'))
      end

      it 'handles the error and logs it' do
        allow(Rails.logger).to receive(:error)

        expect { subject.send_email }.not_to raise_error

        expect(Rails.logger).to have_received(:error).with('Pega Status Update Email Error: Test error')
      end
    end

    context 'when optional keys are missing from payload' do
      let(:data) do
        {
          email: 'pega-team@example.com',
          form_number: '10-10D',
          file_count: 1,
          pega_status: 'Missing',
          date_submitted: Time.zone.now.to_s,
          form_uuid: '4171e61a-03b5-49f3-8717-dbf340310473'
        }
      end

      before do
        allow(Rails).to receive(:env).and_return('staging')
        allow(Flipper).to receive(:enabled?).with(:va_notify_v2_ivc_champva_email).and_return(false)
      end

      it 'includes nil values for missing optional keys in personalisation' do
        expect(VANotify::EmailJob).to receive(:perform_async).with(
          data[:email],
          expected_template_id,
          hash_including(first_name: nil, last_name: nil),
          Settings.vanotify.services.ivc_champva.api_key,
          expected_callback_options
        )
        subject.send_email
      end
    end
  end
end
