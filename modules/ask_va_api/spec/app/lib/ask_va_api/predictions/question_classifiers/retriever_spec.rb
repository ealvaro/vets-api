# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AskVAApi::Predictions::QuestionClassifiers::Retriever do
  describe '#call' do
    let(:valid_question) { 'How do I apply for education benefits?' }
    let(:service_response) do
      {
        'model_name' => 'Category',
        'model_version' => 2,
        'predictions' => {
          '1' => {
            'confidence_level' => 92,
            'name' => 'Education benefits',
            'model_id' => 1
          }
        }
      }
    end

    before do
      allow_any_instance_of(AskVAApi::Predictions::QuestionClassifiers::ServiceClient)
        .to receive(:predict)
        .and_return(service_response)
    end

    def build_retriever(question:)
      described_class.new(question:, model_name: 'Category')
    end

    context 'with valid question' do
      it 'returns result with OK status' do
        retriever = build_retriever(question: valid_question)
        result = retriever.call

        expect(result.status).to eq(:ok)
        expect(result.payload[:modelName]).to eq('Category')
      end

      it 'serializes response to camelCase' do
        retriever = build_retriever(question: valid_question)
        result = retriever.call

        expect(result.payload[:modelName]).to be_present
        expect(result.payload[:predictions]['1'][:confidenceLevel]).to eq(92)
      end
    end

    context 'with blank question' do
      it 'returns 422 unprocessable entity' do
        retriever = build_retriever(question: '')
        result = retriever.call

        expect(result.status).to eq(:unprocessable_entity)
        expect(result.payload[:error][:message]).to include('required')
      end
    end

    context 'with nil question' do
      it 'returns 422 unprocessable entity' do
        retriever = build_retriever(question: nil)
        result = retriever.call

        expect(result.status).to eq(:unprocessable_entity)
        expect(result.payload[:error][:message]).to include('required')
      end
    end

    context 'with question exceeding maximum length' do
      it 'returns 422 unprocessable entity' do
        long_question = 'a' * 10_001
        retriever = build_retriever(question: long_question)
        result = retriever.call

        expect(result.status).to eq(:unprocessable_entity)
        expect(result.payload[:error][:message]).to include('cannot exceed')
      end
    end

    context 'with HTML in question' do
      let(:html_question) { '<script>alert("xss")</script>How do I apply?' }

      it 'sanitizes HTML before calling service and returns OK' do
        expect_any_instance_of(AskVAApi::Predictions::QuestionClassifiers::ServiceClient)
          .to receive(:predict)
          .with(model_name: 'Category', question: 'alert("xss")How do I apply?')
          .and_return(service_response)

        retriever = build_retriever(question: html_question)
        result = retriever.call

        expect(result.status).to eq(:ok)
      end
    end

    context 'when service raises PredictionServiceError' do
      before do
        allow_any_instance_of(AskVAApi::Predictions::QuestionClassifiers::ServiceClient)
          .to receive(:predict)
          .and_raise(AskVAApi::Predictions::QuestionClassifiers::PredictionServiceError.new('Service error', 502))
      end

      it 'returns 502 bad gateway' do
        retriever = build_retriever(question: valid_question)
        result = retriever.call

        expect(result.status).to eq(:bad_gateway)
        expect(result.payload[:error][:message]).to include('Service error')
      end
    end

    context 'when service raises StandardError' do
      before do
        allow_any_instance_of(AskVAApi::Predictions::QuestionClassifiers::ServiceClient)
          .to receive(:predict)
          .and_raise(StandardError, 'Unexpected error')
      end

      it 'returns 500 internal server error' do
        retriever = build_retriever(question: valid_question)
        result = retriever.call

        expect(result.status).to eq(:internal_server_error)
        expect(result.payload[:error][:message]).to include('unexpected')
      end
    end
  end
end
