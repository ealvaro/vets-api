# frozen_string_literal: true

require 'rails_helper'
require 'decision_review/utilities/pdf_validation/service'

# rubocop:disable RSpec/SpecFilePathFormat
RSpec.describe DecisionReview::PdfValidation::Service do
  let(:instance) { described_class.new }
  let(:file) { instance_double(File, read: 'file content') }
  let(:monitor) { instance_double(Logging::Monitor) }

  before do
    allow(Logging::Monitor).to receive(:new).and_return(monitor)
    allow(monitor).to receive(:track_request)
  end

  describe '#validate_pdf_with_lighthouse' do
    context 'when Lighthouse returns a successful response' do
      it 'returns the response' do
        allow(instance).to receive(:perform).and_return(OpenStruct.new(status: 200))
        expect(instance.validate_pdf_with_lighthouse(file)).to be_truthy
      end

      it 'increments the total StatsD counter' do
        allow(instance).to receive(:perform).and_return(OpenStruct.new(status: 200))

        expect { instance.validate_pdf_with_lighthouse(file) }.to trigger_statsd_increment(
          'api.decision_review.pdf_validation.validate_pdf_with_lighthouse.total'
        )
      end
    end

    context 'when Lighthouse returns a validation error' do
      let(:error_body) do
        {
          'errors' => [
            { 'detail' => 'Document is not a valid PDF' },
            { 'detail' => 'Document is empty' }
          ]
        }
      end

      it 'raises UnprocessableEntity with validation details' do
        allow(instance).to receive(:perform).and_raise(
          Common::Client::Errors::ClientError.new(nil, 422, error_body)
        )

        expect { instance.validate_pdf_with_lighthouse(file) }.to raise_error(
          Common::Exceptions::UnprocessableEntity
        ) do |error|
          expect(error.errors.first.detail).to eq("Document is not a valid PDF\nDocument is empty")
          expect(error.errors.first.source).to eq('FormAttachment.lighthouse_validation.invalid_pdf')
        end

        expect(monitor).to have_received(:track_request).with(
          :error,
          'Decision Review Upload failed PDF validation.',
          'api.decision_review.pdf_validation.validate_pdf_with_lighthouse.pdf_validation_failure',
          hash_including(validation_failure_detail: "Document is not a valid PDF\nDocument is empty")
        )
      end

      it 'increments the fail StatsD counter' do
        allow(instance).to receive(:perform).and_raise(
          Common::Client::Errors::ClientError.new(nil, 422, error_body)
        )

        expect { instance.validate_pdf_with_lighthouse(file) }.to raise_error(
          Common::Exceptions::UnprocessableEntity
        ).and trigger_statsd_increment(
          'api.decision_review.pdf_validation.validate_pdf_with_lighthouse.fail',
          tags: ['error:CommonClientErrorsClientError', 'status:422']
        ).and trigger_statsd_increment(
          'api.decision_review.pdf_validation.validate_pdf_with_lighthouse.total'
        )
      end
    end

    context 'when Lighthouse returns a 429 rate limit error' do
      let(:error_body) { { 'message' => 'Rate limit exceeded' } }

      it 'raises UnprocessableEntity with a generic failure message' do
        allow(instance).to receive(:perform).and_raise(
          Common::Client::Errors::ClientError.new(nil, 429, error_body)
        )

        expect { instance.validate_pdf_with_lighthouse(file) }.to raise_error(
          Common::Exceptions::UnprocessableEntity
        ) do |error|
          expect(error.errors.first.detail).to eq('Something went wrong...')
          expect(error.errors.first.source).to eq('FormAttachment.lighthouse_validation.invalid_pdf')
        end

        expect(monitor).to have_received(:track_request).with(
          :error,
          'Decision Review Upload failed PDF validation.',
          'api.decision_review.pdf_validation.validate_pdf_with_lighthouse.pdf_validation_failure',
          hash_including(validation_failure_detail: 'Something went wrong...')
        )
      end

      it 'increments the fail StatsD counter with status tag' do
        allow(instance).to receive(:perform).and_raise(
          Common::Client::Errors::ClientError.new(nil, 429, error_body)
        )

        expect { instance.validate_pdf_with_lighthouse(file) }.to raise_error(
          Common::Exceptions::UnprocessableEntity
        ).and trigger_statsd_increment(
          'api.decision_review.pdf_validation.validate_pdf_with_lighthouse.fail',
          tags: ['error:CommonClientErrorsClientError', 'status:429']
        )
      end
    end

    context 'when Lighthouse returns a ClientError with nil body' do
      it 'raises UnprocessableEntity with a generic failure message' do
        allow(instance).to receive(:perform).and_raise(
          Common::Client::Errors::ClientError.new(nil, 500, nil)
        )

        expect { instance.validate_pdf_with_lighthouse(file) }.to raise_error(
          Common::Exceptions::UnprocessableEntity
        ) do |error|
          expect(error.errors.first.detail).to eq('Something went wrong...')
        end

        expect(monitor).to have_received(:track_request).with(
          :error,
          'Decision Review Upload failed PDF validation.',
          'api.decision_review.pdf_validation.validate_pdf_with_lighthouse.pdf_validation_failure',
          hash_including(validation_failure_detail: 'Something went wrong...')
        )
      end
    end

    context 'when an unexpected error occurs' do
      it 'raises UnprocessableEntity with a generic failure message' do
        allow(instance).to receive(:perform).and_raise(StandardError.new('unexpected'))

        expect { instance.validate_pdf_with_lighthouse(file) }.to raise_error(
          Common::Exceptions::UnprocessableEntity
        ) do |error|
          expect(error.errors.first.detail).to eq('Something went wrong...')
          expect(error.errors.first.source).to eq('FormAttachment.lighthouse_validation.unknown_error')
        end

        expect(monitor).to have_received(:track_request).with(
          :error,
          'Decision Review Upload failed with an unexpected failure case. Investigation Required.',
          'api.decision_review.pdf_validation.validate_pdf_with_lighthouse.unexpected_failure',
          hash_including(error: 'unexpected')
        )
      end

      it 'increments the fail StatsD counter' do
        allow(instance).to receive(:perform).and_raise(StandardError.new('unexpected'))

        expect { instance.validate_pdf_with_lighthouse(file) }.to raise_error(
          Common::Exceptions::UnprocessableEntity
        ).and trigger_statsd_increment(
          'api.decision_review.pdf_validation.validate_pdf_with_lighthouse.fail',
          tags: ['error:StandardError']
        ).and trigger_statsd_increment(
          'api.decision_review.pdf_validation.validate_pdf_with_lighthouse.total'
        )
      end
    end
  end
end
# rubocop:enable RSpec/SpecFilePathFormat
