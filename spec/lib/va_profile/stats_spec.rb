# frozen_string_literal: true

require 'rails_helper'
require 'va_profile/stats'

describe VAProfile::Stats do
  let(:statsd_prefix) { VAProfile::Stats::STATSD_KEY_PREFIX }

  describe '.increment' do
    it 'increments the StatsD VAProfile counter' do
      bucket1 = 'exceptions'
      bucket2 = 'VET360_ADDR133'

      expect { described_class.increment(bucket1, bucket2) }.to trigger_statsd_increment(
        "#{statsd_prefix}.#{bucket1}.#{bucket2.downcase}"
      )
    end

    it 'increments the StatsD VAProfile counter with a variable number of buckets passed' do
      bucket1 = 'bucket1'
      bucket2 = 'bucket2'
      bucket3 = 'bucket3'
      bucket4 = 'bucket4'

      expect { described_class.increment(bucket1, bucket2, bucket3, bucket4) }.to trigger_statsd_increment(
        "#{statsd_prefix}.#{bucket1}.#{bucket2}.#{bucket3}.#{bucket4}"
      )
    end
  end

  describe '.increment_transaction_results' do
    let(:success_status) { described_class::FINAL_SUCCESS.first }
    let(:failure_status) { described_class::FINAL_FAILURE.first }

    context 'when response contains a final success status' do
      it 'increments the StatsD VAProfile posts_and_puts success counter' do
        response = raw_va_profile_transaction_response(success_status)

        expect { described_class.increment_transaction_results(response) }.to trigger_statsd_increment(
          "#{statsd_prefix}.posts_and_puts.success"
        )
      end
    end

    context 'when response contains a final failure status' do
      it 'increments the StatsD Vet360 posts_and_puts failure counter' do
        response = raw_va_profile_transaction_response(failure_status)

        expect { described_class.increment_transaction_results(response) }.to trigger_statsd_increment(
          "#{statsd_prefix}.posts_and_puts.failure"
        )
      end
    end

    context 'when response is neither a success nor failure status' do
      it 'does not increment the StatsD Vet360 posts_and_puts counters', :aggregate_failures do
        response = raw_va_profile_transaction_response('RECEIVED')

        expect { described_class.increment_transaction_results(response) }.not_to trigger_statsd_increment(
          "#{statsd_prefix}.posts_and_puts.success"
        )
        expect { described_class.increment_transaction_results(response) }.not_to trigger_statsd_increment(
          "#{statsd_prefix}.posts_and_puts.failure"
        )
      end
    end

    context 'when response body is nil' do
      it 'does not increment the StatsD Vet360 posts_and_puts counters', :aggregate_failures do
        expect { described_class.increment_transaction_results(nil) }.not_to trigger_statsd_increment(
          "#{statsd_prefix}.posts_and_puts.success"
        )
        expect { described_class.increment_transaction_results(nil) }.not_to trigger_statsd_increment(
          "#{statsd_prefix}.posts_and_puts.failure"
        )
      end
    end

    context 'when bucket1 is provided as init_vet360_id' do
      let(:init_vet360) { 'init_vet360_id' }

      it 'increments the StatsD Vet360 init_vet360_id success counter' do
        response = raw_va_profile_transaction_response(success_status)

        expect { described_class.increment_transaction_results(response, init_vet360) }.to trigger_statsd_increment(
          "#{statsd_prefix}.#{init_vet360}.success"
        )
      end

      it 'increments the StatsD Vet360 init_vet360_id failure counter' do
        response = raw_va_profile_transaction_response(failure_status)

        expect { described_class.increment_transaction_results(response, init_vet360) }.to trigger_statsd_increment(
          "#{statsd_prefix}.#{init_vet360}.failure"
        )
      end
    end

    context 'when path contains a recognized contact type' do
      it 'tags success metrics with the contact type' do
        response = raw_va_profile_transaction_response(success_status)

        expect { described_class.increment_transaction_results(response, path: 'telephones/status/123') }
          .to trigger_statsd_increment(
            "#{statsd_prefix}.posts_and_puts.success",
            tags: ['contact_type:telephone']
          )
      end

      it 'tags failure metrics with the contact type' do
        response = raw_va_profile_transaction_response(failure_status)

        expect { described_class.increment_transaction_results(response, path: 'emails/status/456') }
          .to trigger_statsd_increment(
            "#{statsd_prefix}.posts_and_puts.failure",
            tags: ['contact_type:email']
          )
      end

      it 'ignores unrecognized path segments' do
        response = raw_va_profile_transaction_response(success_status)

        expect { described_class.increment_transaction_results(response, path: 'status/789') }
          .to trigger_statsd_increment(
            "#{statsd_prefix}.posts_and_puts.success",
            tags: nil
          )
      end
    end

    context 'when failure response includes error codes' do
      it 'tags failure metrics with the error code' do
        response = raw_va_profile_transaction_response_with_messages(
          failure_status,
          [{ 'code' => 'ADDR306', 'key' => 'addressBio.lowConfidenceScore', 'severity' => 'ERROR' }]
        )

        expect { described_class.increment_transaction_results(response, path: 'addresses/status/123') }
          .to trigger_statsd_increment(
            "#{statsd_prefix}.posts_and_puts.failure",
            tags: %w[contact_type:address error_code:ADDR306]
          )
      end

      it 'does not tag success metrics with error codes even if messages are present' do
        response = raw_va_profile_transaction_response_with_messages(
          success_status,
          [{ 'code' => 'SOME_CODE', 'severity' => 'INFO' }]
        )

        expect { described_class.increment_transaction_results(response, path: 'telephones/status/123') }
          .to trigger_statsd_increment(
            "#{statsd_prefix}.posts_and_puts.success",
            tags: ['contact_type:telephone']
          )
      end

      it 'handles failure response with no tx_messages' do
        response = raw_va_profile_transaction_response(failure_status)

        expect { described_class.increment_transaction_results(response, path: 'emails/status/456') }
          .to trigger_statsd_increment(
            "#{statsd_prefix}.posts_and_puts.failure",
            tags: ['contact_type:email']
          )
      end

      it 'tags failure with error code only when no path is provided' do
        response = raw_va_profile_transaction_response_with_messages(
          failure_status,
          [{ 'code' => 'CORE103', 'key' => '_CUF_NOT_FOUND', 'severity' => 'ERROR' }]
        )

        expect { described_class.increment_transaction_results(response) }
          .to trigger_statsd_increment(
            "#{statsd_prefix}.posts_and_puts.failure",
            tags: ['error_code:CORE103']
          )
      end

      it 'drops error codes that do not match the safe pattern' do
        response = raw_va_profile_transaction_response_with_messages(
          failure_status,
          [{ 'code' => 'some invalid code with spaces!', 'severity' => 'ERROR' }]
        )

        expect { described_class.increment_transaction_results(response, path: 'addresses/status/123') }
          .to trigger_statsd_increment(
            "#{statsd_prefix}.posts_and_puts.failure",
            tags: ['contact_type:address']
          )
      end

      it 'drops error codes exceeding 20 characters' do
        response = raw_va_profile_transaction_response_with_messages(
          failure_status,
          [{ 'code' => 'A' * 21, 'severity' => 'ERROR' }]
        )

        expect { described_class.increment_transaction_results(response, path: 'addresses/status/123') }
          .to trigger_statsd_increment(
            "#{statsd_prefix}.posts_and_puts.failure",
            tags: ['contact_type:address']
          )
      end
    end

    context 'with alternate final statuses' do
      it 'tags COMPLETED_NO_CHANGES_DETECTED as success with contact type' do
        response = raw_va_profile_transaction_response('COMPLETED_NO_CHANGES_DETECTED')

        expect { described_class.increment_transaction_results(response, path: 'telephones/status/123') }
          .to trigger_statsd_increment(
            "#{statsd_prefix}.posts_and_puts.success",
            tags: ['contact_type:telephone']
          )
      end

      it 'tags COMPLETED_FAILURE with contact type and error code' do
        response = raw_va_profile_transaction_response_with_messages(
          'COMPLETED_FAILURE',
          [{ 'code' => 'ADDRVAL112', 'severity' => 'ERROR' }]
        )

        expect { described_class.increment_transaction_results(response, path: 'addresses/status/123') }
          .to trigger_statsd_increment(
            "#{statsd_prefix}.posts_and_puts.failure",
            tags: %w[contact_type:address error_code:ADDRVAL112]
          )
      end
    end
  end

  describe '.increment_exception' do
    it 'increments the StatsD Vet360 exceptions counter' do
      tag = 'VET360_ADDR133'

      expect { described_class.increment_exception(tag) }.to trigger_statsd_increment(
        "#{statsd_prefix}.exceptions"
      )
    end
  end
end

def raw_va_profile_transaction_response(tx_status)
  OpenStruct.new(body: { 'tx_status' => tx_status })
end

def raw_va_profile_transaction_response_with_messages(tx_status, messages)
  OpenStruct.new(body: { 'tx_status' => tx_status, 'tx_messages' => messages })
end
