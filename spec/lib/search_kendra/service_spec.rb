# frozen_string_literal: true

require 'rails_helper'
require 'lib/search/shared_examples_for_pagination'
require 'search_kendra/service'

describe SearchKendra::Service do
  subject { described_class.new(query) }

  let(:query) { 'benefits' }

  let(:client) { instance_double(Aws::Kendra::Client) }

  let(:config) do
    instance_double(
      SearchKendra::Configuration,
      client:,
      index_id: 'TEST_INDEX'
    )
  end

  let(:query_result) do
    Aws::Kendra::Types::QueryResult.new(
      total_number_of_results: 90
    )
  end

  let(:kendra_response) do
    double(data: query_result)
  end

  before do
    allow(SearchKendra::Configuration)
      .to receive(:instance)
      .and_return(config)

    allow(client)
      .to receive(:query)
      .and_return(kendra_response)
  end

  describe '#results' do
    context 'when successful' do
      it_behaves_like 'pagination data'

      it 'returns search results', :aggregate_failures do
        response = subject.results

        expect(response).to be_a(Search::ResultsResponse)
        expect(response.status).to eq(200)
      end
    end

    context 'when Kendra throttles requests' do
      let(:throttling_error) do
        error = Aws::Kendra::Errors::ThrottlingException.allocate
        allow(error).to receive(:message).and_return('rate exceeded')
        error
      end

      before do
        allow(client)
          .to receive(:query)
          .and_raise(throttling_error)
      end

      it 'increments the StatsD exception counter' do
        allow_any_instance_of(described_class)
          .to receive(:raise_backend_exception)
          .and_return(nil)

        expect { subject.results }.to trigger_statsd_increment(
          "#{described_class::STATSD_KEY_PREFIX}.exceptions"
        )
      end
    end

    [
      [Aws::Kendra::Errors::InternalServerException, 'SEARCH_KENDRA_INTERNALSERVEREXCEPTION', 500],
      [Aws::Kendra::Errors::AccessDeniedException, 'SEARCH_KENDRA_ACCESSDENIEDEXCEPTION', 403],
      [Aws::Kendra::Errors::ConflictException, 'SEARCH_KENDRA_CONFLICTEXCEPTION', 400],
      [Aws::Kendra::Errors::ResourceNotFoundException, 'SEARCH_KENDRA_RESOURCENOTFOUNDEXCEPTION', 404],
      [Aws::Kendra::Errors::ServiceQuotaExceededException, 'SEARCH_KENDRA_SERVICEQUOTAEXCEEDEDEXCEPTION', 429],
      [Aws::Kendra::Errors::ValidationException, 'SEARCH_KENDRA_VALIDATIONEXCEPTION', 400],
      [Aws::Kendra::Errors::ThrottlingException, 'SEARCH_KENDRA_THROTTLINGEXCEPTION', 429]
    ].each do |error_class, expected_code, expected_status|
      context "when Kendra raises #{error_class.name.demodulize}" do
        let(:service_error) do
          error = error_class.allocate
          allow(error).to receive(:message).and_return('an error occurred')
          error
        end

        before do
          allow(client)
            .to receive(:query)
            .and_raise(service_error)
        end

        it 'raises a BackendServiceException with the expected code and status', :aggregate_failures do
          expect { subject.results }.to raise_error do |e|
            expect(e).to be_a(Common::Exceptions::BackendServiceException)
            expect(e.errors.first.code).to eq(expected_code)
            expect(e.status_code).to eq(expected_status)
          end
        end

        it 'logs the error to Rails.logger' do
          expect(Rails.logger).to receive(:error).with(
            'External service error',
            hash_including(
              search: 'general_search_query_error',
              message: 'an error occurred',
              index_id: 'TEST_INDEX',
              name: expected_code
            )
          )

          expect { subject.results }.to raise_error(Common::Exceptions::BackendServiceException)
        end
      end
    end

    context 'when Kendra raises exception not defined for locale' do
      let(:service_error) do
        error = Aws::Kendra::Errors::FeaturedResultsConflictException.allocate
        allow(error).to receive(:message).and_return('an error occurred')
        error
      end

      before do
        allow(client)
          .to receive(:query)
          .and_raise(service_error)
      end

      it 'raises a BackendServiceException with the default code and status', :aggregate_failures do
        expect { subject.results }.to raise_error do |e|
          expect(e).to be_a(Common::Exceptions::BackendServiceException)
          expect(e.errors.first.code).to eq('VA900')
          expect(e.status_code).to eq(400)
        end
      end

      it 'logs the error to Rails.logger' do
        expect(Rails.logger).to receive(:error).with(
          'External service error',
          hash_including(
            search: 'general_search_query_error',
            message: 'an error occurred',
            index_id: 'TEST_INDEX',
            name: 'SEARCH_KENDRA_FEATUREDRESULTSCONFLICTEXCEPTION'
          )
        )

        expect { subject.results }.to raise_error(Common::Exceptions::BackendServiceException)
      end
    end

    context 'when an unexpected, non-AWS error occurs' do
      let(:unexpected_error) { StandardError.new('something unrelated broke') }

      before do
        allow(client)
          .to receive(:query)
          .and_raise(unexpected_error)
      end

      it 're-raises the original error without wrapping it' do
        expect { subject.results }.to raise_error(StandardError, 'something unrelated broke')
      end

      it 'does not call raise_backend_exception' do
        expect_any_instance_of(described_class).not_to receive(:raise_backend_exception)

        expect { subject.results }.to raise_error(StandardError)
      end
    end
  end

  describe '#query_params' do
    let(:query) { 'DD 214 test@example.com 123-45-6789' }

    it 'redacts PII from query parameter' do
      params = subject.send(:query_params)

      expect(params[:query_text]).to eq('dd 214 [REDACTED - email] [REDACTED - ssn]')
    end

    it 'normalizes query' do
      service = described_class.new(' DD 214 ')
      params = service.send(:query_params)

      expect(params[:query_text]).to eq('dd214')
    end

    it 'includes the configured index_id' do
      params = subject.send(:query_params)

      expect(params[:index_id]).to eq('TEST_INDEX')
    end

    it 'includes the configured page_size' do
      params = subject.send(:query_params)

      expect(params[:page_size]).to eq(Search::Pagination::ENTRIES_PER_PAGE)
    end

    context 'page_number' do
      it 'defaults to 1 when no page is given' do
        params = subject.send(:query_params)

        expect(params[:page_number]).to eq(1)
      end

      it 'uses the given page when greater than 1' do
        service = described_class.new(query, 3)
        params = service.send(:query_params)

        expect(params[:page_number]).to eq(3)
      end

      it 'never goes below 1' do
        service = described_class.new(query, 0)
        params = service.send(:query_params)

        expect(params[:page_number]).to eq(1)
      end
    end
  end
end
