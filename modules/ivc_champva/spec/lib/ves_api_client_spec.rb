# frozen_string_literal: true

require 'rails_helper'
require 'ves_api/client'

RSpec.describe IvcChampva::VesApi::Client do
  let(:client) { described_class.new }
  let(:transaction_uuid) { '12345' }
  let(:ves_request_data) { instance_double(IvcChampva::VesRequest, to_json: '{}', application_uuid: '12345') }

  describe '#submit_1010d' do
    before do
      allow(client).to receive(:connection).and_return(double(post: response))
    end

    context 'successful response from VES' do
      let(:response) { instance_double(Faraday::Response, status: 200, body: '{}') }

      it 'does not raise an error' do
        expect do
          client.submit_1010d(transaction_uuid, ves_request_data)
        end.not_to raise_error
      end

      it 'calls monitor.track_request' do
        expect(client.monitor).to receive(:track_request).with(
          'info',
          "IVC ChampVa Forms - Successful submission to VES for form #{transaction_uuid}",
          'api.ivc_champva_form.ves_response.success',
          call_location: anything,
          form_uuid: transaction_uuid,
          messages: '{}',
          status: 200
        )

        client.submit_1010d(transaction_uuid, ves_request_data)
      end

      it 'does not return nil on success' do
        expect(client.submit_1010d(transaction_uuid, ves_request_data).nil?).to be(false)
      end
    end

    context '400 response from VES' do
      let(:response) { instance_double(Faraday::Response, status: 400, body: '{}') }

      it 'raises a VesApiError' do
        expect do
          client.submit_1010d(transaction_uuid, ves_request_data)
        end.to raise_error(IvcChampva::VesApi::VesApiError)
      end

      it 'calls monitor.track_request' do
        expect(client.monitor).to receive(:track_request).with(
          'error',
          "IVC ChampVa Forms - Error on submission to VES for form #{transaction_uuid}",
          'api.ivc_champva_form.ves_response.failure',
          call_location: anything,
          form_uuid: transaction_uuid,
          messages: '{}',
          status: 400
        )

        expect do
          client.submit_1010d(transaction_uuid, ves_request_data)
        end.to raise_error(IvcChampva::VesApi::VesApiError)
      end
    end

    context 'not authorized response from VES' do
      let(:response) { instance_double(Faraday::Response, status: 403, body: '{}') }

      it 'raises a VesApiError' do
        expect do
          client.submit_1010d(transaction_uuid, ves_request_data)
        end.to raise_error(IvcChampva::VesApi::VesApiError)
      end
    end

    context '500 response from VES' do
      let(:response) { instance_double(Faraday::Response, status: 500, body: '{}') }

      it 'raises a VesApiError' do
        expect do
          client.submit_1010d(transaction_uuid, ves_request_data)
        end.to raise_error(IvcChampva::VesApi::VesApiError)
      end
    end
  end

  describe '#submit_7959c' do
    let(:ves_ohi_request_data) { instance_double(IvcChampva::VesOhiRequest, to_json: '{}', application_uuid: '12345') }

    before do
      allow(client).to receive(:connection).and_return(double(post: response))
    end

    context 'successful response from VES' do
      let(:response) { instance_double(Faraday::Response, status: 200, body: '{"messages":[]}') }

      it 'does not raise an error' do
        expect do
          client.submit_7959c(transaction_uuid, ves_ohi_request_data)
        end.not_to raise_error
      end

      it 'calls monitor.track_request for success' do
        expect(client.monitor).to receive(:track_request).with(
          'info',
          "IVC ChampVa Forms - Successful submission to VES for form #{transaction_uuid}",
          'api.ivc_champva_form.ves_response.success',
          call_location: anything,
          form_uuid: transaction_uuid,
          messages: '{"messages":[]}',
          status: 200
        )

        client.submit_7959c(transaction_uuid, ves_ohi_request_data)
      end

      it 'returns the response on success' do
        result = client.submit_7959c(transaction_uuid, ves_ohi_request_data)
        expect(result).to eq(response)
        expect(result.status).to eq(200)
      end
    end

    context '400 response from VES' do
      let(:error_body) { '{"messages":[{"code":"INVALID_REQUEST","description":"Invalid data"}]}' }
      let(:response) { instance_double(Faraday::Response, status: 400, body: error_body) }

      it 'raises a VesApiError' do
        expect do
          client.submit_7959c(transaction_uuid, ves_ohi_request_data)
        end.to raise_error(IvcChampva::VesApi::VesApiError)
      end

      it 'calls monitor.track_request for failure' do
        expect(client.monitor).to receive(:track_request).with(
          'error',
          "IVC ChampVa Forms - Error on submission to VES for form #{transaction_uuid}",
          'api.ivc_champva_form.ves_response.failure',
          call_location: anything,
          form_uuid: transaction_uuid,
          messages: error_body,
          status: 400
        )

        expect do
          client.submit_7959c(transaction_uuid, ves_ohi_request_data)
        end.to raise_error(IvcChampva::VesApi::VesApiError)
      end
    end

    context 'not authorized response from VES' do
      let(:response) { instance_double(Faraday::Response, status: 403, body: '{"messages":[]}') }

      it 'raises a VesApiError' do
        expect do
          client.submit_7959c(transaction_uuid, ves_ohi_request_data)
        end.to raise_error(IvcChampva::VesApi::VesApiError)
      end
    end

    context '500 response from VES' do
      let(:error_body) { '{"messages":[{"code":"INTERNAL_ERROR","description":"Server error"}]}' }
      let(:response) { instance_double(Faraday::Response, status: 500, body: error_body) }

      it 'raises a VesApiError' do
        expect do
          client.submit_7959c(transaction_uuid, ves_ohi_request_data)
        end.to raise_error(IvcChampva::VesApi::VesApiError)
      end
    end

    context 'posts to the correct endpoint' do
      let(:response) { instance_double(Faraday::Response, status: 200, body: '{}') }
      let(:mock_connection) { double('connection') }

      before do
        allow(client).to receive(:connection).and_return(mock_connection)
      end

      it 'posts to the champva-insurance-form endpoint' do
        expect(mock_connection).to receive(:post).with(%r{/ves-vfmp-app-svc/champva-insurance-form}).and_yield(
          double('request', headers: {}, body: nil).as_null_object
        ).and_return(response)

        client.submit_7959c(transaction_uuid, ves_ohi_request_data)
      end
    end
  end

  describe 'headers' do
    it 'returns the right headers with provided api key' do
      result = client.headers('the_right_uuid', 'my_api_key')

      expect(result[:content_type]).to eq('application/json')
      expect(result['apiKey']).to eq('my_api_key')
      expect(result['transactionUUId']).to eq('the_right_uuid')
    end
  end

  describe 'ohi_api_key' do
    it 'returns ohi_api_key when configured' do
      expect(client.ohi_api_key).to eq('fake_ohi_api_key')
    end

    it 'falls back to api_key when ohi_api_key is not configured' do
      allow(client.settings).to receive(:ohi_api_key).and_return(nil)

      expect(client.ohi_api_key).to eq('fake_api_key')
    end

    it 'falls back to api_key when ohi_api_key is blank' do
      allow(client.settings).to receive(:ohi_api_key).and_return('')

      expect(client.ohi_api_key).to eq('fake_api_key')
    end
  end

  describe '#get_icns_for_transaction' do
    let(:response_body) do
      '{"data":[{"icn":"0000001200603250V008079000000","personUUID":"682","personType":"SPONSOR"},' \
        '{"icn":"0000001200603251V181504000000","personUUID":"638","personType":"BENEFICIARY"}],"messages":[]}'
    end

    before do
      allow(client).to receive(:connection).and_return(double(get: response))
    end

    context 'successful response from VES' do
      let(:response) { instance_double(Faraday::Response, status: 200, body: response_body) }

      it 'returns parsed data array' do
        result = client.get_icns_for_transaction(transaction_uuid)
        expect(result).to be_an(Array)
        expect(result.size).to eq(2)
        expect(result.first['icn']).to eq('0000001200603250V008079000000')
      end
    end

    context 'non-200 response from VES' do
      let(:response) { instance_double(Faraday::Response, status: 404, body: '{}') }

      it 'raises a VesApiError' do
        expect do
          client.get_icns_for_transaction(transaction_uuid)
        end.to raise_error(IvcChampva::VesApi::VesApiError)
      end
    end

    context 'application not yet processed (empty data)' do
      let(:response) { instance_double(Faraday::Response, status: 200, body: '{"data":[],"messages":[]}') }

      it 'raises a VesApplicationPendingError' do
        expect do
          client.get_icns_for_transaction(transaction_uuid)
        end.to raise_error(IvcChampva::VesApi::VesApplicationPendingError)
      end
    end
  end

  describe '#icn_lookup_headers' do
    context 'when api_key is configured (production/dev)' do
      it 'includes the apiKey header' do
        result = client.send(:icn_lookup_headers, transaction_uuid)
        expect(result['apiKey']).to eq('fake_api_key')
        expect(result['transactionUUId']).to eq(transaction_uuid)
        expect(result[:content_type]).to eq('application/json')
      end
    end

    context 'when api_key is blank (staging)' do
      before { allow(client.settings).to receive(:api_key).and_return(nil) }

      it 'omits the apiKey header' do
        result = client.send(:icn_lookup_headers, transaction_uuid)
        expect(result.key?('apiKey')).to be(false)
        expect(result['transactionUUId']).to eq(transaction_uuid)
      end
    end
  end

  describe '#get_ee_summary' do
    let(:icn) { '0000001013836784V369083000000' }
    let(:success_body) do
      {
        'data' => {
          'vfmpProgramsInfo' => {
            'relationships' => [
              {
                'champvaEligibilities' => [
                  {
                    'status' => 'Ineligible',
                    'reason' => 'No current school letter',
                    'sponsor' => {
                      'icn' => '0000001013836108V943512000000',
                      'champvaStatus' => 'ELIGIBLE',
                      'champvaReason' => 'P&T'
                    }
                  }
                ]
              }
            ]
          }
        },
        'messages' => []
      }.to_json
    end

    before do
      allow(client).to receive(:connection).and_return(double(get: response))
    end

    context 'successful response with data' do
      let(:response) { instance_double(Faraday::Response, status: 200, body: success_body) }

      it 'returns the parsed data hash' do
        result = client.get_ee_summary(icn:)
        expect(result).to be_a(Hash)
        eligibility = result.dig('vfmpProgramsInfo', 'relationships', 0, 'champvaEligibilities', 0)
        expect(eligibility['status']).to eq('Ineligible')
      end

      it 'passes regionIdOrOffset when provided' do
        mock_conn = double('connection')
        allow(client).to receive(:connection).and_return(mock_conn)
        expect(mock_conn).to receive(:get)
          .with(%r{/eesummary/CSTChampvaEligibility},
                hash_including(regionIdOrOffset: 'GMT-6'))
          .and_yield(double('req', headers: {}).as_null_object)
          .and_return(response)
        client.get_ee_summary(icn:, region_id_or_offset: 'GMT-6')
      end

      it 'defaults the dataset to CSTChampvaEligibility' do
        mock_conn = double('connection')
        allow(client).to receive(:connection).and_return(mock_conn)
        expect(mock_conn).to receive(:get)
          .with(%r{/eesummary/CSTChampvaEligibility}, anything)
          .and_yield(double('req', headers: {}).as_null_object)
          .and_return(response)
        client.get_ee_summary(icn:)
      end

      it 'uses an explicit dataset override' do
        mock_conn = double('connection')
        allow(client).to receive(:connection).and_return(mock_conn)
        expect(mock_conn).to receive(:get)
          .with(%r{/eesummary/ChampvaDigitalCardData}, anything)
          .and_yield(double('req', headers: {}).as_null_object)
          .and_return(response)
        client.get_ee_summary(icn:, dataset: 'ChampvaDigitalCardData')
      end
    end

    context 'application not yet processed (nil data)' do
      let(:response) { instance_double(Faraday::Response, status: 200, body: '{"data":null,"messages":[]}') }

      it 'raises a VesApplicationPendingError' do
        expect do
          client.get_ee_summary(icn:)
        end.to raise_error(IvcChampva::VesApi::VesApplicationPendingError)
      end
    end

    context 'non-200 response from VES' do
      let(:response) { instance_double(Faraday::Response, status: 500, body: '{}') }

      it 'raises a VesApiError' do
        expect do
          client.get_ee_summary(icn:)
        end.to raise_error(IvcChampva::VesApi::VesApiError)
      end
    end

    context 'timeout from VES' do
      let(:response) { instance_double(Faraday::Response, status: 200, body: '{}') }

      before do
        allow(client).to receive(:connection).and_raise(Faraday::TimeoutError)
      end

      it 'raises a VesApiTimeoutError' do
        expect do
          client.get_ee_summary(icn:)
        end.to raise_error(IvcChampva::VesApi::VesApiTimeoutError)
      end
    end

    context 'connection failure from VES' do
      let(:response) { instance_double(Faraday::Response, status: 200, body: '{}') }

      before do
        allow(client).to receive(:connection).and_raise(Faraday::ConnectionFailed.new('connection failed'))
      end

      it 'raises a VesApiTimeoutError' do
        expect do
          client.get_ee_summary(icn:)
        end.to raise_error(IvcChampva::VesApi::VesApiTimeoutError)
      end
    end
  end

  describe '#ee_summary_headers' do
    context 'when api_key is configured (production/dev)' do
      it 'includes the apiKey header' do
        result = client.send(:ee_summary_headers)
        expect(result['apiKey']).to eq('fake_api_key')
        expect(result[:content_type]).to eq('application/json')
        expect(result['accept']).to eq('application/json')
      end

      it 'does not include a transactionUUId header' do
        result = client.send(:ee_summary_headers)
        expect(result.key?('transactionUUId')).to be(false)
      end
    end

    context 'when api_key is blank (staging)' do
      before { allow(client.settings).to receive(:api_key).and_return(nil) }

      it 'omits the apiKey header' do
        result = client.send(:ee_summary_headers)
        expect(result.key?('apiKey')).to be(false)
      end
    end
  end

  # Temporary, delete me
  # This test is used to hit the production endpoint when running locally.
  # It can be removed once we have some real code that uses the VES API client.
  describe 'hit the production endpoint', skip: 'this is useful as a way to hit the API during local development' do
    let(:forced_headers) do
      {
        :content_type => 'application/json',
        # use the following line when running locally tp pull the key from an environment variable
        'x-api-key' => ENV.fetch('VES_API_KEY'), # to set: export VES_API_KEY=insert1the2api3key4here
        'transactionUUId' => '1234'
      }
    end

    before do
      allow_any_instance_of(IvcChampva::VesApi::Client).to receive(:headers).with(anything)
                                                                            .and_return(forced_headers)
    end
  end
end
