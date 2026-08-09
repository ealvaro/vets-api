# frozen_string_literal: true

require 'rails_helper'
require 'lighthouse/letters_generator/download_failure'

RSpec.describe Lighthouse::LettersGenerator::DownloadFailure do
  # A reason code with no matching locale entry renders "Translation missing: ..." to the veteran
  # as their error message in production, where raise_on_missing_translations is off. Under test
  # it's on (config/environments/test.rb:62), so a missing key raises here instead — either way
  # this is the guard that stops a typo in a reason code or a locale key from shipping.
  describe '.message_for' do
    it 'resolves real copy for every reason' do
      described_class::REASONS.each do |reason|
        expect { described_class.message_for(reason) }.not_to raise_error
        expect(described_class.message_for(reason)).to be_present
      end
    end
  end

  describe '.classify' do
    {
      'The following errors are present: Missing Identifier Data' => 'missing_identifier_data',
      'no BirlsRecord with valid releasedActiveDutyDate/branchOfService' => 'missing_service_history',
      'The following errors are present: No valid address found' => 'no_valid_address',
      'VA Profile Contact Info Service Unavailable' => 'va_profile_unavailable',
      'Backend Service Error' => 'backend_service_error',
      'BGS connection error' => 'backend_service_error'
    }.each do |detail, code|
      it "classifies #{detail.inspect} as #{code}" do
        expect(described_class.classify(detail)).to eq(code)
      end
    end

    it 'falls back to unknown for an unrecognized reason' do
      expect(described_class.classify('Something we have never seen')).to eq('unknown')
    end

    # Guessing wide is worse than falling through: telling a veteran whose record is durably
    # broken to "try again later" is the behavior this class exists to stop. An unrecognized
    # VA Profile message must land in unknown, whose copy is safe for either cause.
    it 'does not assume an unrecognized VA Profile message is transient' do
      expect(described_class.classify('VA Profile returned something new')).to eq('unknown')
    end

    it 'falls back to unknown when there is no detail at all' do
      expect(described_class.classify(nil)).to eq('unknown')
    end

    it 'matches the most specific reason when a detail could hit several patterns' do
      detail = 'The following errors are present: Missing Identifier Data, Backend Service Error'

      expect(described_class.classify(detail)).to eq('missing_identifier_data')
    end
  end

  describe '.enrich' do
    let(:upstream_error) do
      Common::Exceptions::UnprocessableEntity.new(
        errors: [{
          type: 'https://api.va.gov/services/va-letter-generator/errors/required-data-exception',
          title: 'Required Data Error',
          status: '422',
          code: '422',
          detail: 'The following errors are present: No valid address found'
        }]
      )
    end

    it 'replaces the upstream detail with a veteran-facing message' do
      error = described_class.enrich(upstream_error, letter_type: 'BENEFIT_SUMMARY')

      expect(error.errors.first[:detail]).to eq(described_class.message_for(described_class::NO_VALID_ADDRESS))
    end

    it 'adds the reason code without disturbing the fields clients already read' do
      error = described_class.enrich(upstream_error, letter_type: 'BENEFIT_SUMMARY')

      expect(error.errors.first).to include(
        reason: 'no_valid_address',
        title: 'Required Data Error',
        status: '422',
        code: '422',
        type: 'https://api.va.gov/services/va-letter-generator/errors/required-data-exception'
      )
    end

    it 'still raises a 422' do
      error = described_class.enrich(upstream_error, letter_type: 'BENEFIT_SUMMARY')

      expect(error).to be_an_instance_of(Common::Exceptions::UnprocessableEntity)
      expect(error.status_code).to eq(422)
    end

    it 'increments StatsD tagged by reason, letter type, and source app' do
      expect { described_class.enrich(upstream_error, letter_type: 'BENEFIT_SUMMARY') }
        .to trigger_statsd_increment(
          'api.letters_generator.download.failure',
          tags: %w[reason:no_valid_address letter_type:benefit_summary source_app:unknown]
        )
    end

    it 'tags the source app when the request carried an allowlisted one' do
      RequestStore.store['additional_request_attributes'] = { 'source' => 'mobile' }

      expect { described_class.enrich(upstream_error, letter_type: 'BENEFIT_SUMMARY') }
        .to trigger_statsd_increment(
          'api.letters_generator.download.failure',
          tags: %w[reason:no_valid_address letter_type:benefit_summary source_app:mobile]
        )
    end

    it 'does not tag an unrecognized source app' do
      RequestStore.store['additional_request_attributes'] = { 'source' => 'not-a-real-app' }

      expect { described_class.enrich(upstream_error, letter_type: 'BENEFIT_SUMMARY') }
        .to trigger_statsd_increment(
          'api.letters_generator.download.failure',
          tags: %w[reason:no_valid_address letter_type:benefit_summary source_app:unknown]
        )
    end

    it 'logs the classified reason' do
      allow(Rails.logger).to receive(:warn)

      described_class.enrich(upstream_error, letter_type: 'BENEFIT_SUMMARY')

      expect(Rails.logger).to have_received(:warn).with(
        'Lighthouse letters generator rejected a letter download',
        hash_including(reason: 'no_valid_address', letter_type: 'benefit_summary')
      )
    end

    # The generator echoes submitted field values back in `detail` — its 400s quote the ICN —
    # and DataScrubber does not redact ICNs (ICN is in its REGEX map but not in PATTERN_ORDER).
    # Lighthouse::ServiceException already logs the raw body for this same request, so this line
    # carries the classification only rather than a second copy of untrusted upstream text.
    it 'keeps upstream free text out of the log line' do
      allow(Rails.logger).to receive(:warn)
      error = Common::Exceptions::UnprocessableEntity.new(
        errors: [{ status: '422', detail: 'No letter for icn 1012667145V762142' }]
      )

      described_class.enrich(error, letter_type: 'BENEFIT_SUMMARY')

      expect(Rails.logger).to have_received(:warn) do |_message, payload|
        expect(payload.values.join(' ')).not_to include('1012667145V762142')
      end
    end

    context 'when the upstream response carried no parseable errors' do
      let(:upstream_error) { Common::Exceptions::UnprocessableEntity.new }

      it 'still returns an actionable error tagged unknown' do
        error = described_class.enrich(upstream_error, letter_type: 'BENEFIT_SUMMARY')

        expect(error.errors.first).to include(
          reason: 'unknown',
          detail: described_class.message_for(described_class::UNKNOWN),
          status: '422'
        )
      end
    end
  end
end
