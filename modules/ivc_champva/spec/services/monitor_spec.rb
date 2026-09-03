# frozen_string_literal: true

require 'rails_helper'
require_relative '../../lib/ivc_champva/monitor'

RSpec.describe IvcChampva::Monitor do
  let(:monitor) { described_class.new }

  describe '#track_request' do
    it 'delegates to the parent class track_request method' do
      allow(StatsD).to receive(:increment)
      allow(Rails.logger).to receive(:info)

      monitor.send(:track_request, 'info', 'Test message', 'test.key', foo: 'bar')

      expect(StatsD).to have_received(:increment).with('test.key', tags: anything)
      expect(Rails.logger).to have_received(:info).with('Test message', anything)
    end
  end

  describe '#track_insert_form' do
    it 'calls track_request with correct parameters' do
      form_uuid = '12345678-1234-5678-1234-567812345678'
      form_id = 'vha_10_10d'

      additional_context = {
        form_uuid:,
        form_id:
      }

      expect(monitor).to receive(:track_request).with(
        'info',
        "IVC ChampVA Forms - #{form_id} inserted into database",
        "#{IvcChampva::Monitor::STATS_KEY}.insert_form",
        call_location: anything,
        **additional_context
      )

      monitor.track_insert_form(form_uuid, form_id)
    end

    it 'handles nil values gracefully' do
      expect(monitor).to receive(:track_request)
      expect { monitor.track_insert_form(nil, nil) }.not_to raise_error
    end
  end

  describe '#track_update_status' do
    it 'calls track_request with correct parameters' do
      form_uuid = '12345678-1234-5678-1234-567812345678'
      status = 'Processed'

      additional_context = {
        form_uuid:,
        status:
      }

      expect(monitor).to receive(:track_request).with(
        'info',
        "IVC ChampVA Forms - #{form_uuid} status updated to #{status}",
        "#{IvcChampva::Monitor::STATS_KEY}.update_status",
        call_location: anything,
        **additional_context
      )

      monitor.track_update_status(form_uuid, status)
    end

    it 'handles nil status gracefully' do
      form_uuid = '12345678-1234-5678-1234-567812345678'
      expect(monitor).to receive(:track_request)
      expect { monitor.track_update_status(form_uuid, nil) }.not_to raise_error
    end
  end

  describe '#track_email_sent' do
    it 'calls track_request with correct parameters' do
      form_id = '10-10d'
      form_uuid = '12345678-1234-5678-1234-567812345678'
      delivery_status = 'delivered'
      notification_type = 'confirmation'

      additional_context = {
        form_id:,
        form_uuid:,
        delivery_status:,
        notification_type:
      }

      expect(monitor).to receive(:track_request).with(
        'info',
        "IVC ChampVA Forms - #{delivery_status} #{form_id} #{notification_type}\n" \
        "                    email for submission with UUID #{form_uuid}",
        "#{IvcChampva::Monitor::STATS_KEY}.email_sent",
        call_location: anything,
        **additional_context
      )

      monitor.track_email_sent(form_id, form_uuid, delivery_status, notification_type)
    end

    it 'handles nil values gracefully' do
      expect(monitor).to receive(:track_request)
      expect { monitor.track_email_sent(nil, nil, nil, nil) }.not_to raise_error
    end
  end

  describe '#track_missing_status_email_sent' do
    it 'calls track_request with correct parameters' do
      form_id = 'vha_10_10d'

      additional_context = {
        form_id:
      }

      expect(monitor).to receive(:track_request).with(
        'info',
        "IVC ChampVA Forms - #{form_id} missing status failure email sent",
        "#{IvcChampva::Monitor::STATS_KEY}.form_missing_status_email_sent",
        call_location: anything,
        **additional_context
      )

      monitor.track_missing_status_email_sent(form_id)
    end

    it 'handles nil form_id gracefully' do
      expect(monitor).to receive(:track_request)
      expect { monitor.track_missing_status_email_sent(nil) }.not_to raise_error
    end
  end

  describe '#track_pega_alert_email_sent' do
    it 'calls track_request with correct parameters' do
      form_id = 'vha_10_10d'

      additional_context = {
        form_id:
      }

      expect(monitor).to receive(:track_request).with(
        'info',
        "IVC ChampVA Forms - #{form_id} missing pega status alert sent",
        "#{IvcChampva::Monitor::STATS_KEY}.form_missing_pega_status_alert_email_sent",
        call_location: anything,
        **additional_context
      )

      monitor.track_pega_alert_email_sent(form_id)
    end

    it 'handles nil form_id gracefully' do
      expect(monitor).to receive(:track_request)
      expect { monitor.track_pega_alert_email_sent(nil) }.not_to raise_error
    end
  end

  describe '#track_pega_alert_email_failed' do
    it 'calls track_request with correct parameters' do
      form_id = 'vha_10_10d'
      status = 'permanent-failure'
      status_reason = 'It done broke real good'

      additional_context = {
        form_id:,
        status:,
        status_reason:
      }

      expect(monitor).to receive(:track_request).with(
        'warn',
        "IVC ChampVA Forms - #{form_id} missing pega status alert failed to send, " \
        "status: #{status}, reason: #{status_reason}",
        "#{IvcChampva::Monitor::STATS_KEY}.form_missing_pega_status_alert_email_failed",
        call_location: anything,
        **additional_context
      )

      monitor.track_pega_alert_email_failed(form_id, status, status_reason)
    end

    it 'handles nil arguments gracefully' do
      expect(monitor).to receive(:track_request)
      expect { monitor.track_pega_alert_email_failed(nil, nil, nil) }.not_to raise_error
    end
  end

  describe '#track_send_zsf_notification_to_pega' do
    it 'calls track_request with correct parameters' do
      form_uuid = '12345678-1234-5678-1234-567812345678'
      template_id = 'fake-template'

      additional_context = {
        form_uuid:,
        template_id:
      }

      expect(monitor).to receive(:track_request).with(
        'info',
        "IVC ChampVA Forms - Sent notification to Pega for submission #{form_uuid}",
        "#{IvcChampva::Monitor::STATS_KEY}.send_zsf_notification_to_pega",
        call_location: anything,
        **additional_context
      )

      monitor.track_send_zsf_notification_to_pega(form_uuid, template_id)
    end
  end

  describe '#track_failed_send_zsf_notification_to_pega' do
    it 'calls track_request with correct parameters' do
      form_uuid = '12345678-1234-5678-1234-567812345678'
      template_id = 'fake-template'

      additional_context = {
        form_uuid:,
        template_id:
      }

      expect(monitor).to receive(:track_request).with(
        'warn',
        "IVC ChampVA Forms - Failed to send notification to Pega for submission #{form_uuid}",
        "#{IvcChampva::Monitor::STATS_KEY}.failed_send_zsf_notification_to_pega",
        call_location: anything,
        **additional_context
      )

      monitor.track_failed_send_zsf_notification_to_pega(form_uuid, template_id)
    end
  end

  describe '#track_all_successful_s3_uploads' do
    it 'calls track_request with correct parameters' do
      key = 'test_form.pdf'

      additional_context = {
        key:
      }

      expect(monitor).to receive(:track_request).with(
        'info',
        "IVC ChampVA Forms - uploaded into S3 bucket #{key}",
        "#{IvcChampva::Monitor::STATS_KEY}.s3_upload.success",
        call_location: anything,
        **additional_context
      )

      monitor.track_all_successful_s3_uploads(key)
    end
  end

  describe '#track_s3_put_object_error' do
    let(:error) { StandardError.new('Test Error Message') }
    let(:key) { 'test_file.pdf' }

    it 'calls track_request with correct parameters for basic error' do
      additional_context = {
        key:,
        error_message: error.message,
        error_class: error.class.name,
        backtrace: error.backtrace&.join("\n")
      }

      expect(monitor).to receive(:track_request).with(
        'error',
        'IVC ChampVA Forms - S3 PutObject failure',
        "#{IvcChampva::Monitor::STATS_KEY}.s3_upload.failure",
        call_location: anything,
        **additional_context
      )

      monitor.track_s3_put_object_error(key, error, nil)
    end

    it 'includes response information when provided' do
      response = double('response', status: 500)
      allow(response).to receive(:respond_to?).with(:status).and_return(true)
      allow(response).to receive(:respond_to?).with(:body).and_return(true)
      response_body = double('body')
      allow(response_body).to receive(:respond_to?).with(:read).and_return(true)
      allow(response_body).to receive(:read).and_return('Error body')
      allow(response).to receive(:body).and_return(response_body)

      additional_context = {
        key:,
        error_message: error.message,
        error_class: error.class.name,
        backtrace: error.backtrace&.join("\n"),
        status_code: 500,
        response_body: 'Error body'
      }

      expect(monitor).to receive(:track_request).with(
        'error',
        'IVC ChampVA Forms - S3 PutObject failure',
        "#{IvcChampva::Monitor::STATS_KEY}.s3_upload.failure",
        call_location: anything,
        **additional_context
      )

      monitor.track_s3_put_object_error(key, error, response)
    end

    it 'handles response without body' do
      response = double('response', status: 500)
      allow(response).to receive(:respond_to?).with(:status).and_return(true)
      allow(response).to receive(:respond_to?).with(:body).and_return(false)

      expect(monitor).to receive(:track_request)
      monitor.track_s3_put_object_error(key, error, response)
    end

    it 'handles response with non-readable body' do
      response = double('response', status: 500)
      allow(response).to receive(:respond_to?).with(:status).and_return(true)
      allow(response).to receive(:respond_to?).with(:body).and_return(true)
      response_body = double('body')
      allow(response_body).to receive(:respond_to?).with(:read).and_return(false)
      allow(response).to receive(:body).and_return(response_body)

      expect(monitor).to receive(:track_request)
      monitor.track_s3_put_object_error(key, error, response)
    end
  end

  describe '#track_s3_upload_file_error' do
    let(:key) { 'test_form.pdf' }
    let(:error) { StandardError.new('Test error') }

    it 'calls track_request with correct parameters' do
      additional_context = {
        key:,
        error_message: error.message,
        error_class: error.class.name,
        backtrace: error.backtrace&.join("\n")
      }

      expect(monitor).to receive(:track_request).with(
        'error',
        'IVC ChampVA Forms - S3 UploadFile failure',
        "#{IvcChampva::Monitor::STATS_KEY}.s3_upload.failure",
        call_location: anything,
        **additional_context
      )

      monitor.track_s3_upload_file_error(key, error)
    end

    it 'handles error with nil backtrace' do
      allow(error).to receive(:backtrace).and_return(nil)
      expect(monitor).to receive(:track_request)
      monitor.track_s3_upload_file_error(key, error)
    end
  end

  describe '#track_s3_upload_error' do
    it 'calls track_request with correct parameters' do
      form_uuid = '12345678-1234-5678-1234-567812345678'
      s3_err = 'Failed to upload file to S3'

      additional_context = {
        form_uuid:,
        s3_err:
      }

      expect(monitor).to receive(:track_request).with(
        'warn',
        "IVC ChampVa Forms - failed to upload all documents for submission: #{form_uuid}",
        "#{IvcChampva::Monitor::STATS_KEY}.s3_upload_error",
        call_location: anything,
        **additional_context
      )

      monitor.track_s3_upload_error(form_uuid, s3_err)
    end

    it 'handles edge cases with empty or nil values' do
      [
        ['', ''],
        [nil, nil],
        ['12345678-1234-5678-1234-567812345678', nil],
        [nil, 'Some error message']
      ].each do |form_uuid, s3_err|
        expect(monitor).to receive(:track_request)
        monitor.track_s3_upload_error(form_uuid, s3_err)
      end
    end
  end

  describe '#track_pdf_stamper_error' do
    it 'calls track_request with correct parameters' do
      form_uuid = '12345678-1234-5678-1234-567812345678'
      err_message = 'oh no'

      additional_context = {
        form_uuid:,
        err_message:
      }

      expect(monitor).to receive(:track_request).with(
        'warn',
        "IVC ChampVa Forms - an error occurred during pdf stamping: #{form_uuid}",
        "#{IvcChampva::Monitor::STATS_KEY}.pdf_stamper_error",
        call_location: anything,
        **additional_context
      )

      monitor.track_pdf_stamper_error(form_uuid, err_message)
    end

    it 'handles edge cases with empty or nil values' do
      [
        ['', ''],
        [nil, nil],
        ['12345678-1234-5678-1234-567812345678', nil],
        [nil, 'Some error message']
      ].each do |form_uuid, err_message|
        expect(monitor).to receive(:track_request)
        monitor.track_pdf_stamper_error(form_uuid, err_message)
      end
    end
  end

  describe '#track_ves_response' do
    it 'calls track_request with success parameters for 200 status' do
      form_uuid = '12345678-1234-5678-1234-567812345678'
      status = 200
      messages = '{"messages": [{"code": "abc123", "key": "someKey", "text": "someText"}]}'

      additional_context = {
        form_uuid:,
        status:,
        messages:
      }

      expect(monitor).to receive(:track_request).with(
        'info',
        "IVC ChampVa Forms - Successful submission to VES for form #{form_uuid}",
        "#{IvcChampva::Monitor::STATS_KEY}.ves_response.success",
        call_location: anything,
        **additional_context
      )

      monitor.track_ves_response(form_uuid, status, messages)
    end

    it 'calls track_request with failure parameters for non-200 status' do
      form_uuid = '12345678-1234-5678-1234-567812345678'
      status = 500
      messages = '{"error": "Internal Server Error"}'

      additional_context = {
        form_uuid:,
        status:,
        messages:
      }

      expect(monitor).to receive(:track_request).with(
        'error',
        "IVC ChampVa Forms - Error on submission to VES for form #{form_uuid}",
        "#{IvcChampva::Monitor::STATS_KEY}.ves_response.failure",
        call_location: anything,
        **additional_context
      )

      monitor.track_ves_response(form_uuid, status, messages)
    end

    it 'handles nil status as failure' do
      form_uuid = '12345678-1234-5678-1234-567812345678'
      status = nil
      messages = nil

      additional_context = {
        form_uuid:,
        status:,
        messages:
      }

      expect(monitor).to receive(:track_request).with(
        'error',
        "IVC ChampVa Forms - Error on submission to VES for form #{form_uuid}",
        "#{IvcChampva::Monitor::STATS_KEY}.ves_response.failure",
        call_location: anything,
        **additional_context
      )

      monitor.track_ves_response(form_uuid, status, messages)
    end
  end

  # Integration tests with actual logging and StatsD
  describe 'integration tests' do
    before do
      allow(StatsD).to receive(:increment)
      allow(Rails.logger).to receive(:info)
      allow(Rails.logger).to receive(:warn)
      allow(Rails.logger).to receive(:error)
    end

    it 'actually logs and tracks metrics for track_insert_form' do
      form_uuid = '12345678-1234-5678-1234-567812345678'
      form_id = 'vha_10_10d'

      monitor.track_insert_form(form_uuid, form_id)

      expect(StatsD).to have_received(:increment).with(
        "#{IvcChampva::Monitor::STATS_KEY}.insert_form",
        tags: array_including('service:veteran-ivc-champva-forms')
      )
      expect(Rails.logger).to have_received(:info).with(
        "IVC ChampVA Forms - #{form_id} inserted into database",
        hash_including(
          statsd: "#{IvcChampva::Monitor::STATS_KEY}.insert_form",
          service: 'veteran-ivc-champva-forms'
        )
      )
    end

    it 'actually logs and tracks metrics for track_ves_response success' do
      form_uuid = '12345678-1234-5678-1234-567812345678'
      status = 200
      messages = '{"status": "success"}'

      monitor.track_ves_response(form_uuid, status, messages)

      expect(StatsD).to have_received(:increment).with(
        "#{IvcChampva::Monitor::STATS_KEY}.ves_response.success",
        tags: array_including('service:veteran-ivc-champva-forms')
      )
      expect(Rails.logger).to have_received(:info)
    end

    it 'actually logs and tracks metrics for track_s3_upload_error' do
      form_uuid = '12345678-1234-5678-1234-567812345678'
      s3_err = 'Upload failed'

      monitor.track_s3_upload_error(form_uuid, s3_err)

      expect(StatsD).to have_received(:increment).with(
        "#{IvcChampva::Monitor::STATS_KEY}.s3_upload_error",
        tags: array_including('service:veteran-ivc-champva-forms')
      )
      expect(Rails.logger).to have_received(:warn)
    end
  end

  # These assert through to StatsD rather than mocking track_request, because the behavior worth
  # protecting is that the pivot dimensions arrive as tags. Logging::Monitor builds the tags before
  # it filters the log context, so tags reach Datadog unredacted while context does not; a spec
  # that stopped at track_request would not catch a regression that moved them into context.
  describe '#track_ves_call_failure' do
    before do
      allow(StatsD).to receive(:increment)
      allow(Rails.logger).to receive(:error)
    end

    it 'increments the failure metric tagged with the operation, reason, and error class' do
      monitor.track_ves_call_failure('ee_summary', :upstream_error, StandardError.new('boom'))

      expect(StatsD).to have_received(:increment).with(
        "#{IvcChampva::Monitor::STATS_KEY}.ves_call.failure",
        tags: array_including('ves_operation:ee_summary', 'reason:upstream_error', 'error_class:StandardError')
      )
      expect(Rails.logger).to have_received(:error).with(
        'IVC ChampVa Forms - VES ee_summary call failed: upstream_error',
        hash_including(statsd: "#{IvcChampva::Monitor::STATS_KEY}.ves_call.failure")
      )
    end

    it 'omits the error class tag when no exception is supplied' do
      monitor.track_ves_call_failure('icn_lookup', :upstream_timeout)

      expect(StatsD).to have_received(:increment).with(
        "#{IvcChampva::Monitor::STATS_KEY}.ves_call.failure",
        tags: array_including('ves_operation:icn_lookup', 'reason:upstream_timeout')
      )
      expect(StatsD).not_to have_received(:increment).with(
        anything, tags: array_including(/\Aerror_class:/)
      )
    end
  end

  describe '#track_get_benefits_card' do
    it 'increments the get metric' do
      allow(StatsD).to receive(:increment)
      allow(Rails.logger).to receive(:info)

      monitor.track_get_benefits_card

      expect(StatsD).to have_received(:increment).with(
        "#{IvcChampva::Monitor::STATS_KEY}.benefits_card.get",
        tags: array_including('service:veteran-ivc-champva-forms')
      )
      expect(Rails.logger).to have_received(:info).with('IVC ChampVA Forms - benefits card data retrieved', anything)
    end
  end

  describe '#track_benefits_card_error' do
    before do
      allow(StatsD).to receive(:increment)
      allow(Rails.logger).to receive(:warn)
      allow(Rails.logger).to receive(:error)
    end

    it 'increments the rejected metric at warn for a 4xx' do
      monitor.track_benefits_card_error('expired', 404)

      expect(StatsD).to have_received(:increment).with(
        "#{IvcChampva::Monitor::STATS_KEY}.benefits_card.rejected",
        tags: array_including('reason:expired', 'http_status:404')
      )
      expect(Rails.logger).to have_received(:warn).with(
        'IVC ChampVA Forms - benefits card rejected: expired', anything
      )
      expect(Rails.logger).not_to have_received(:error)
    end

    it 'increments the failed metric at error for a 5xx' do
      monitor.track_benefits_card_error('upstream_error', 502)

      expect(StatsD).to have_received(:increment).with(
        "#{IvcChampva::Monitor::STATS_KEY}.benefits_card.failed",
        tags: array_including('reason:upstream_error', 'http_status:502')
      )
      expect(Rails.logger).to have_received(:error).with(
        'IVC ChampVA Forms - benefits card failed: upstream_error', anything
      )
      expect(Rails.logger).not_to have_received(:warn)
    end

    it 'keeps the two severities on separate metrics so alerting can target only failures' do
      monitor.track_benefits_card_error('not_enrolled', 404)
      monitor.track_benefits_card_error('upstream_timeout', 504)

      expect(StatsD).to have_received(:increment).with(
        "#{IvcChampva::Monitor::STATS_KEY}.benefits_card.rejected", anything
      ).once
      expect(StatsD).to have_received(:increment).with(
        "#{IvcChampva::Monitor::STATS_KEY}.benefits_card.failed", anything
      ).once
    end

    it 'merges extra context into the log payload' do
      monitor.track_benefits_card_error('upstream_error', 502, { error_class: 'IvcChampva::VesApi::VesApiError' })

      expect(Rails.logger).to have_received(:error).with(
        anything,
        hash_including(statsd: "#{IvcChampva::Monitor::STATS_KEY}.benefits_card.failed")
      )
    end
  end
end
