# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ErrorHandling do
  let(:dummy_class) do
    Class.new(ApplicationController) do
      include ErrorHandling

      # Stubs for controller methods used by the concern
      attr_accessor :current_user

      def controller_path
        'travel_pay/v0/claims'
      end

      def action_name
        'index'
      end
    end
  end

  let(:instance) { dummy_class.new }

  describe '#extract_correlation_id' do
    context 'when the exception has no response' do
      it 'returns nil' do
        error = ArgumentError.new('bad input')
        expect(instance.send(:extract_correlation_id, error)).to be_nil
      end
    end

    context 'when the correlation ID is in the request headers' do
      it 'returns the outbound X-Correlation-ID' do
        cid = 'abc-123-request'
        error = Faraday::BadRequestError.new(
          'bad request',
          {
            status: 400,
            request: { headers: { 'X-Correlation-ID' => cid } },
            body: nil
          }
        )

        expect(instance.send(:extract_correlation_id, error)).to eq(cid)
      end
    end

    context 'when the correlation ID is in the response body' do
      it 'returns the correlationId from the parsed JSON body' do
        cid = 'abc-123-response-body'
        body = { 'correlationId' => cid, 'statusCode' => 400, 'message' => 'Bad Request' }.to_json
        error = Faraday::BadRequestError.new(
          'bad request',
          {
            status: 400,
            request: { headers: {} },
            body:
          }
        )

        expect(instance.send(:extract_correlation_id, error)).to eq(cid)
      end

      it 'handles an already-parsed hash body' do
        cid = 'abc-123-parsed'
        error = Faraday::BadRequestError.new(
          'bad request',
          {
            status: 400,
            request: { headers: {} },
            body: { 'correlationId' => cid }
          }
        )

        expect(instance.send(:extract_correlation_id, error)).to eq(cid)
      end
    end

    context 'when the response body cannot be parsed' do
      it 'logs a warning and returns nil' do
        error = Faraday::BadRequestError.new(
          'bad request',
          {
            status: 400,
            request: { headers: {} },
            body: 'not valid json{{'
          }
        )

        expect(Rails.logger).to receive(:warn).with(
          'Failed to parse BTSSS response body for correlation ID',
          error: instance_of(String)
        )

        expect(instance.send(:extract_correlation_id, error)).to be_nil
      end
    end

    context 'when the request header is present but the body also has a correlationId' do
      it 'prefers the request header' do
        request_cid = 'from-request'
        body_cid = 'from-body'
        error = Faraday::BadRequestError.new(
          'bad request',
          {
            status: 400,
            request: { headers: { 'X-Correlation-ID' => request_cid } },
            body: { 'correlationId' => body_cid }.to_json
          }
        )

        expect(instance.send(:extract_correlation_id, error)).to eq(request_cid)
      end
    end
  end
end
