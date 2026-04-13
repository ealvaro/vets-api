# frozen_string_literal: true

require 'rails_helper'
require 'pega_api/client'

RSpec.describe IvcChampva::PegaApi::Client do
  subject { described_class.new }

  describe 'get_report' do
    let(:body200and200) do # pega api response with HTTP status 200 and alternate status 200
      fixture_path = Rails.root.join('modules', 'ivc_champva', 'spec', 'fixtures', 'pega_api_json',
                                     'report_response_200_200.json')
      fixture_path.read
    end

    let(:body200and500) do # pega api response with HTTP status 200 and alternate status 500
      fixture_path = Rails.root.join('modules', 'ivc_champva', 'spec', 'fixtures', 'pega_api_json',
                                     'report_response_200_500.json')
      fixture_path.read
    end

    let(:body403) do # pega api response with HTTP status 403 forbidden
      fixture_path = Rails.root.join('modules', 'ivc_champva', 'spec', 'fixtures', 'pega_api_json',
                                     'report_response_403.json')
      fixture_path.read
    end

    context 'successful response from pega' do
      let(:faraday_response) { double('Faraday::Response', status: 200, body: body200and200) }

      before do
        allow_any_instance_of(Faraday::Connection).to receive(:post).with(anything).and_return(faraday_response)
      end

      it 'returns the body as an array of hashes' do
        result = subject.get_report(Date.new(2024, 11, 1), Date.new(2024, 12, 31))

        expect(result[0]['Creation Date']).to eq('2024-11-27T08:42:11.372000')
        expect(result[0]['PEGA Case ID']).to eq('D-55824')
        expect(result[0]['Status']).to eq('Open')
      end
    end

    context 'unsuccessful pega response with bad HTTP status' do
      let(:faraday_response) { double('Faraday::Response', status: 403, body: body403) }

      before do
        allow_any_instance_of(Faraday::Connection).to receive(:post).with(anything).and_return(faraday_response)
      end

      it 'raises error when response is 404' do
        expect { subject.get_report(nil, nil) }.to raise_error(IvcChampva::PegaApi::PegaApiError)
      end
    end

    context 'unsuccessful pega response with bad alternate status' do
      let(:faraday_response) { double('Faraday::Response', status: 200, body: body200and500) }

      before do
        allow_any_instance_of(Faraday::Connection).to receive(:post).with(anything).and_return(faraday_response)
      end

      it 'raises error when alternate status is 500' do
        expect { subject.get_report(nil, nil) }.to raise_error(IvcChampva::PegaApi::PegaApiError)
      end
    end

    context 'when checking record_has_matching_report with a valid form' do
      let(:forms) { create_list(:ivc_champva_form, 1, pega_status: 'Processed', created_at: Date.new(2024, 11, 27)) }
      let(:faraday_response) { double('Faraday::Response', status: 200, body: body200and200) }

      before do
        allow_any_instance_of(Faraday::Connection).to receive(:post).with(anything).and_return(faraday_response)
      end

      it 'returns an array of results where UUID matches requested record' do
        forms[0].update(form_uuid: '9a0e9790-7e09-46ba-afcb-121a0ddd0d3b')
        result = subject.record_has_matching_report(forms[0])
        expect(result[0]['UUID']).to eq('9a0e9790-7e09-46ba-afcb-121a0e+')
      end

      it 'calls get_report with date range one day before and after record.created_at' do
        record = double('IvcChampvaForm', created_at: Time.zone.parse('2024-06-10'), form_uuid: 'abc-123')
        client = described_class.new
        allow(client).to receive(:get_report).and_return([{ 'some' => 'report' }])

        client.record_has_matching_report(record)

        expect(client).to have_received(:get_report).with(
          '06/09/2024',
          '06/11/2024',
          '',
          'abc-123'
        )
      end
    end
  end

  describe 'headers' do
    it 'returns the right headers' do
      result = subject.headers(Date.new(2024, 11, 1), Date.new(2024, 12, 31))

      expect(result[:content_type]).to eq('application/json')
      expect(result['x-api-key']).to eq('fake_api_key')
      expect(result['date_start']).to eq('2024-11-01')
      expect(result['date_end']).to eq('2024-12-31')
      expect(result['case_id']).to eq('')
      expect(result['uuid']).to eq('')
    end

    it 'returns the right headers with nil dates' do
      result = subject.headers(nil, nil)

      expect(result[:content_type]).to eq('application/json')
      expect(result['x-api-key']).to eq('fake_api_key')
      expect(result['date_start']).to eq('')
      expect(result['date_end']).to eq('')
      expect(result['case_id']).to eq('')
      expect(result['uuid']).to eq('')
    end
  end

  describe 'get_status_by_uuid' do
    let(:uuid) { 'ea6ee9e7-1f56-4539-9c3c-173c43c4593c' }

    let(:mock_status_body) do
      '{"statusCode": 200, "body": "[{\"PEGA Case ID\": \"D-100018\", \"Status\": \"Open\", ' \
        '\"Doctype\": \"OHI Certificate\", \"Deternimation Type\": \"Document Identification error\", ' \
        '\"Eligibity Date\": null, \"UUID\": \"ea6ee9e7-1f56-4539-9c3c-173c43c4593c\"}, {\"PEGA Case ID\": ' \
        '\"D-100017\", \"Status\": \"Open\", \"Doctype\": \"OHI Certificate\", \"Deternimation Type\": ' \
        '\"Document Identification error\", \"Eligibity Date\": null, ' \
        '\"UUID\": \"ea6ee9e7-1f56-4539-9c3c-173c43c4593c\"}, {\"PEGA Case ID\": \"D-99021\", \"Status\": \"Open\", ' \
        '\"Doctype\": \"Application under 65\", \"Deternimation Type\": ' \
        '\"Eligiblity denied/Additional information needed\", \"Eligibity Date\": \"20260226\", ' \
        '\"UUID\": \"ea6ee9e7-1f56-4539-9c3c-173c43c4593c\"}]"}'
    end

    context 'when Pega returns a valid 200 envelope with stringified body array' do
      let(:faraday_response) { double('Faraday::Response', status: 200, body: mock_status_body) }

      before do
        allow_any_instance_of(Faraday::Connection).to receive(:get).with(anything).and_return(faraday_response)
      end

      it 'returns parsed case rows with expected case IDs and statuses' do
        result = subject.get_status_by_uuid(uuid)

        expect(result.size).to eq(3)
        expect(result.map { |row| row['PEGA Case ID'] }).to eq(%w[D-100018 D-100017 D-99021])
        expect(result.map { |row| row['Deternimation Type'] }).to eq(
          ['Document Identification error', 'Document Identification error',
           'Eligiblity denied/Additional information needed']
        )
      end
    end

    context 'when Pega returns 200 HTTP but non-200 envelope statusCode' do
      let(:faraday_response) do
        double('Faraday::Response', status: 200, body: { 'statusCode' => 500, 'body' => 'boom' }.to_json)
      end

      before do
        allow_any_instance_of(Faraday::Connection).to receive(:get).with(anything).and_return(faraday_response)
      end

      it 'raises a PegaApiError' do
        expect { subject.get_status_by_uuid(uuid) }.to raise_error(IvcChampva::PegaApi::PegaApiError)
      end
    end
  end

  # Temporary, delete me
  # This test is used to hit the production endpoint when running locally.
  # It can be removed once we have some real code that uses the Pega API client.
  describe 'hit the production endpoint', skip: 'this is useful as a way to hit the API during local development' do
    let(:forced_headers) do
      {
        :content_type => 'application/json',
        # use the following line when running locally tp pull the key from an environment variable
        'x-api-key' => ENV.fetch('PEGA_API_KEY'), # to set: export PEGA_API_KEY=insert1the2api3key4here
        'date_start' => '', # '2024-11-01', # '11/01/2024',
        'date_end' => '', # '2024-12-31', # '12/07/2024',
        'case_id' => ''
      }
    end

    before do
      allow_any_instance_of(IvcChampva::PegaApi::Client).to receive(:headers).with(anything, anything)
                                                                             .and_return(forced_headers)
    end

    it 'returns report data' do
      VCR.configure do |c|
        c.allow_http_connections_when_no_cassette = true
      end

      result = subject.get_report(Date.new(2024, 11, 1), Date.new(2024, 12, 31))
      expect(result.count).to be_positive

      # byebug # in byebug, type 'p result' to view the response
    end
  end
end
