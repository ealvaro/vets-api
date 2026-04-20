# frozen_string_literal: true

require 'rails_helper'
require_relative '../../support/vcr_helpers'
require 'bd/bd'
require 'claims_api/v2/benefits_documents/service'

RSpec.describe ClaimsApi::FilterVADocumentsConcern do
  # supporting document filtering common methods
  def pre_filtered_uuids(search_docs, letters_response)
    original_search_uuids = search_docs.to_set { |doc| doc[:documentUuid].gsub(/[{}]/, '') }
    original_letters_uuids = letters_response[:data][:documents].to_set { |doc| doc[:documentUuid].gsub(/[{}]/, '') }
    [original_search_uuids, original_letters_uuids]
  end

  def common_filtering_expectations(identifier, original_search_uuids, original_letters_uuids)
    result = subject_instance.filter_va_documents(input_documents, **identifier)

    # Check if there are common documents between search and letters responses
    common_documents = original_search_uuids & original_letters_uuids
    expect(common_documents).to be_present

    # Verify filtering occurred - result should equal search count minus filtered documents
    search_document_count = original_search_uuids.length
    expected_result_count = search_document_count - common_documents.length
    expect(result.length).to eq(expected_result_count)

    # Verify VA-generated documents (from letters_data) are not included in the results
    result_uuids = result.to_set { |doc| doc[:documentUuid].gsub(/[{}]/, '') }
    expect(result_uuids & original_letters_uuids).to be_empty
  end

  # Create a test class that includes the concern
  let(:test_supporting_docs_class) do
    Class.new do
      include ClaimsApi::FilterVADocumentsConcern

      def initialize(benefits_doc_api)
        @benefits_doc_api = benefits_doc_api
      end

      private

      attr_reader :benefits_doc_api
    end
  end

  let(:benefits_doc_api_mock) { instance_double(ClaimsApi::BD) }
  let(:subject_instance) { test_supporting_docs_class.new(benefits_doc_api_mock) }
  let(:file_number) { '796378782' }
  let(:participant_id) { '600045025' }

  describe '#filter_va_documents' do
    let(:va_documents_response) do
      VcrHelpers.load_vcr_response_data(
        'claims_api/bd/claim_with_mixed_documents_letters_search', 1
      )
    end

    # documents from search that have already been unpacked from BD response
    let(:input_documents) do
      VcrHelpers.load_vcr_response_data(
        'claims_api/bd/claim_with_mixed_documents_search', 1
      )[:data][:documents]
    end

    # test both file number and participant id cases
    [
      { file_number: '796378782', expected_params: { file_number: '796378782', participant_id: nil } },
      { participant_id: '600045025', expected_params: { file_number: nil, participant_id: '600045025' } }
    ].each do |test_case|
      identifier = test_case.except(:expected_params)
      context "when the identifier is #{identifier.keys.first}" do
        context 'when documents and VA documents exist' do
          before do
            allow(benefits_doc_api_mock).to receive(:claim_letters_search)
              .with(test_case[:expected_params])
              .and_return(va_documents_response)
          end

          it 'uses the right identifier and filters out documents that match VA documentUuids' do
            pre_filtered_uuids, va_document_uuids = pre_filtered_uuids(input_documents, va_documents_response)

            common_filtering_expectations(identifier, pre_filtered_uuids, va_document_uuids)

            # expect claim_letters_search was called with the right identifier
            expect(benefits_doc_api_mock).to have_received(:claim_letters_search).with(test_case[:expected_params])
          end
        end

        # edge case tests to ensure method handles unexpected or missing data gracefully
        # without filtering out all documents or raising errors
        context 'when no VA documents exist' do
          let(:va_documents_response) do
            {
              data: {
                documents: []
              }
            }
          end

          before do
            allow(benefits_doc_api_mock).to receive(:claim_letters_search)
              .with(test_case[:expected_params])
              .and_return(va_documents_response)
          end

          it 'returns all input documents unchanged' do
            result = subject_instance.filter_va_documents(input_documents, **identifier)

            expect(result).to eq(input_documents)
          end
        end

        context 'when claim_letters_search errors and returns an empty hash' do
          before do
            allow(benefits_doc_api_mock).to receive(:claim_letters_search)
              .with(test_case[:expected_params])
              .and_return({})
          end

          it 'returns all input documents unchanged' do
            result = subject_instance.filter_va_documents(input_documents, **identifier)

            expect(result).to eq(input_documents)
          end
        end

        context 'UUID normalization' do
          let(:input_documents) do
            [
              {
                documentUuid: '{UPPERCASE-UUID-WITH-BRACKETS}'
              },
              {
                documentUuid: 'lowercase-uuid-no-brackets'
              },
              {
                documentUuid: 'MiXeD-CaSe-UUID'
              }
            ]
          end

          let(:va_documents_response) do
            {
              data: {
                documents: [
                  {
                    documentUuid: 'uppercase-uuid-with-brackets'
                  },
                  {
                    documentUuid: '{LOWERCASE-UUID-NO-BRACKETS}'
                  }
                ]
              }
            }
          end

          before do
            allow(benefits_doc_api_mock).to receive(:claim_letters_search)
              .with(test_case[:expected_params])
              .and_return(va_documents_response)
          end

          it 'normalizes UUIDs by removing brackets and converting to lowercase' do
            result = subject_instance.filter_va_documents(input_documents, **identifier)

            # Should filter out first two documents due to UUID normalization matches
            expect(result.length).to eq(1)
            expect(result.first[:documentUuid]).to eq('MiXeD-CaSe-UUID')
          end
        end

        context 'when documentUuid is missing from some documents' do
          let(:input_documents) do
            [
              {
                documentUuid: '{valid-uuid}',
                originalFileName: 'document_with_uuid.pdf'
              },
              {
                # Missing documentUuid
                originalFileName: 'document_without_uuid.pdf'
              }
            ]
          end

          let(:va_documents_response) do
            {
              data: {
                documents: [
                  {
                    documentUuid: 'valid-uuid'
                  }
                ]
              }
            }
          end

          before do
            allow(benefits_doc_api_mock).to receive(:claim_letters_search)
              .with(test_case[:expected_params])
              .and_return(va_documents_response)
          end

          it 'handles documents with missing documentUuid gracefully' do
            result = subject_instance.filter_va_documents(input_documents, **identifier)

            # Should filter out the document with matching UUID, keep the one without UUID
            expect(result.length).to eq(1)
            expect(result.first[:originalFileName]).to eq('document_without_uuid.pdf')
          end
        end
      end
    end
  end
end
