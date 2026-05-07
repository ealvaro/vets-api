# frozen_string_literal: true

require 'rails_helper'
require 'medical_records/lighthouse_client'

describe MedicalRecords::LighthouseClient do
  subject(:client) { described_class.new('1013868614V792025') }

  before do
    described_class.send(:public, *described_class.protected_instance_methods)
  end

  after do
    described_class.send(:protected, :handle_api_errors, :parse_error_diagnostics)
  end

  describe '#initialize' do
    it 'raises ParameterMissing when ICN is blank' do
      expect { described_class.new('') }.to raise_error(Common::Exceptions::ParameterMissing)
    end

    it 'sets the ICN' do
      expect(client.instance_variable_get(:@icn)).to eq('1013868614V792025')
    end
  end

  describe '#handle_api_errors' do
    context 'when response is successful' do
      let(:result) { OpenStruct.new(code: 200) }

      it 'does not raise an exception' do
        expect { client.handle_api_errors(result) }.not_to raise_error
      end
    end

    context 'when response is an error' do
      let(:result) { OpenStruct.new(code: 400, body: { issue: [{ diagnostics: 'Error Message' }] }.to_json) }

      it 'raises a BackendServiceException' do
        expect { client.handle_api_errors(result) }.to raise_error(Common::Exceptions::BackendServiceException)
      end
    end

    context 'when diagnostics are missing in the response' do
      let(:result) { OpenStruct.new(code: 400, body: {}.to_json) }

      it 'handles missing diagnostics gracefully' do
        expect { client.handle_api_errors(result) }.to raise_error(Common::Exceptions::BackendServiceException)
      end
    end

    context 'when response body is HTML instead of JSON' do
      let(:html_body) { '<html><body><h1>500 Internal Server Error</h1></body></html>' }
      let(:result) { OpenStruct.new(code: 500, body: html_body) }

      it 'raises a BackendServiceException with a non-JSON diagnostic message' do
        expect(Rails.logger).to receive(:error).with(
          'MedicalRecords received non-JSON error response',
          hash_including(body_size: html_body.length)
        )
        expect { client.handle_api_errors(result) }.to raise_error(
          Common::Exceptions::BackendServiceException
        ) do |error|
          expect(error.message).to include('Upstream service returned a non-JSON response')
        end
      end
    end

    context 'when response body is non-JSON text' do
      let(:result) { OpenStruct.new(code: 502, body: 'Bad Gateway') }

      it 'raises a BackendServiceException and logs safe metadata' do
        expect(Rails.logger).to receive(:error).with(
          'MedicalRecords received non-JSON error response',
          hash_including(body_size: 11)
        )
        expect { client.handle_api_errors(result) }.to raise_error(Common::Exceptions::BackendServiceException)
      end
    end
  end
end
