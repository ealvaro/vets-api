# frozen_string_literal: true

require 'rails_helper'
require 'debt_management_center/sharepoint/graph/request'
require 'pdf_fill/filler'

RSpec.describe DebtManagementCenter::Sharepoint::Graph::Request do
  let(:request) { described_class.new }

  let(:authentication_settings) do
    double(
      base_url: 'https://login.microsoftonline.com',
      client_id: 'fake-client-id',
      client_secret: 'fake-client-secret',
      tenant_url: '/fake-tenant/oauth2/v2.0/token'
    )
  end

  let(:upload_settings) do
    double(
      base_url: 'https://graph.microsoft.com',
      path: '/v1.0/drives/fake-drive/root:/INCOME%20REVIEW%20CALCULATOR/' \
            'VODA%20Financial%20Management%205655%20for%20VS/'
    )
  end

  let(:graph_settings) do
    double(
      authentication: authentication_settings,
      upload: upload_settings,
      mock: false
    )
  end

  let(:vha_settings) { double(sharepoint_graph: graph_settings) }

  before do
    allow(Settings).to receive(:vha).and_return(vha_settings)
  end

  describe '#settings' do
    it 'returns the SharePoint Graph settings' do
      expect(request.settings).to eq(graph_settings)
    end
  end

  describe '#upload' do
    let(:form_contents) { { 'foo' => 'bar' } }
    let(:form_submission) { create(:debts_api_form5655_submission) }
    let(:station_id) { '123' }

    let(:pdf_path) { '/tmp/5655.pdf' }
    let(:pdf_contents) { '%PDF fake contents' }

    let(:upload_connection) { double('Faraday::Connection') }
    let(:upload_response) { double('Faraday::Response') }

    let(:faraday_request) do
      Struct.new(:headers, :body).new({})
    end

    let(:upload_time) do
      Time.utc(2026, 7, 10, 12, 34, 56)
    end

    let(:expected_upload_path) do
      "#{upload_settings.path.chomp('/')}/20260710T123456_#{form_submission.id}.pdf:/content"
    end

    before do
      allow(Time).to receive(:current).and_return(upload_time)

      allow(request).to receive_messages(
        build_pdf: pdf_path,
        upload_connection:
      )
      allow(request).to receive(:with_monitoring).and_yield

      allow(File).to receive(:binread)
        .with(pdf_path)
        .and_return(pdf_contents)

      allow(File).to receive(:exist?).and_call_original

      allow(File).to receive(:exist?)
        .with(pdf_path)
        .and_return(true)

      allow(File).to receive(:delete)

      allow(StatsD).to receive(:increment)
      allow(Rails.logger).to receive(:error)
    end

    it 'builds and uploads the PDF' do
      allow(upload_connection).to receive(:put) do |path, &block|
        expect(path).to eq(expected_upload_path)

        block.call(faraday_request)

        upload_response
      end

      response = request.upload(
        form_contents:,
        form_submission:,
        station_id:
      )

      expect(request).to have_received(:build_pdf).with(
        form_contents:,
        form_submission:,
        station_id:
      )

      expect(faraday_request.headers['Content-Type'])
        .to eq('application/pdf')

      expect(faraday_request.body)
        .to eq(pdf_contents)

      expect(response)
        .to eq(upload_response)
    end

    it 'increments the success StatsD metric' do
      allow(upload_connection)
        .to receive(:put)
        .and_return(upload_response)

      request.upload(
        form_contents:,
        form_submission:,
        station_id:
      )

      expect(StatsD).to have_received(:increment).with(
        "#{described_class::STATSD_KEY_PREFIX}.success"
      )
    end

    it 'deletes the generated PDF after upload' do
      allow(upload_connection)
        .to receive(:put)
        .and_return(upload_response)

      request.upload(
        form_contents:,
        form_submission:,
        station_id:
      )

      expect(File).to have_received(:delete)
        .with(pdf_path)
    end

    context 'when the upload fails' do
      before do
        allow(upload_connection)
          .to receive(:put)
          .and_raise(StandardError, 'Upload failed')
      end

      it 'increments the failure metric and raises the error' do
        expect do
          request.upload(
            form_contents:,
            form_submission:,
            station_id:
          )
        end.to raise_error(
          StandardError,
          'Upload failed'
        )

        expect(StatsD).to have_received(:increment).with(
          "#{described_class::STATSD_KEY_PREFIX}.failure"
        )
      end

      it 'logs the error' do
        expect do
          request.upload(
            form_contents:,
            form_submission:,
            station_id:
          )
        end.to raise_error(StandardError)

        expect(Rails.logger).to have_received(:error).with(
          'SharePoint Graph upload failed',
          submission_id: form_submission.id,
          message: 'Upload failed'
        )
      end

      it 'deletes the generated PDF' do
        expect do
          request.upload(
            form_contents:,
            form_submission:,
            station_id:
          )
        end.to raise_error(StandardError)

        expect(File).to have_received(:delete)
          .with(pdf_path)
      end
    end
  end

  describe '#build_pdf' do
    let(:form_contents) { { 'foo' => 'bar' } }
    let(:form_submission) { instance_double(DebtsApi::V0::Form5655Submission, id: 123) }
    let(:station_id) { '456' }
    let(:pdf_path) { '/tmp/5655.pdf' }

    it 'builds the 5655 PDF' do
      expect(PdfFill::Filler)
        .to receive(:fill_ancillary_form)
        .with(
          form_contents,
          '123-456',
          '5655'
        )
        .and_return(pdf_path)

      result = request.send(
        :build_pdf,
        form_contents:,
        form_submission:,
        station_id:
      )

      expect(result).to eq(pdf_path)
    end
  end

  describe '#access_token' do
    let(:authentication_connection) do
      double('Faraday::Connection')
    end

    let(:authentication_response) do
      double(
        body: {
          'access_token' => 'fake-access-token'
        }
      )
    end

    let(:faraday_request) do
      Struct.new(:body).new
    end

    before do
      allow(request)
        .to receive(:authentication_connection)
        .and_return(authentication_connection)

      allow(authentication_connection)
        .to receive(:post) do |path, &block|
          expect(path)
            .to eq(authentication_settings.tenant_url)

          block.call(faraday_request)

          authentication_response
        end
    end

    it 'requests an access token' do
      token = request.send(:access_token)

      expect(token)
        .to eq('fake-access-token')

      expect(faraday_request.body).to eq(
        client_id: 'fake-client-id',
        client_secret: 'fake-client-secret',
        scope: 'https://graph.microsoft.com/.default',
        grant_type: 'client_credentials'
      )
    end

    it 'memoizes the access token' do
      request.send(:access_token)
      request.send(:access_token)

      expect(authentication_connection)
        .to have_received(:post)
        .once
    end
  end

  describe '#upload_path' do
    let(:form_submission) do
      instance_double(DebtsApi::V0::Form5655Submission, id: 123)
    end

    before do
      allow(Time)
        .to receive(:current)
        .and_return(
          Time.utc(2026, 7, 10, 12, 34, 56)
        )
    end

    it 'builds the Graph upload path' do
      expect(
        request.send(
          :upload_path,
          form_submission
        )
      ).to eq(
        "#{upload_settings.path.chomp('/')}/20260710T123456_123.pdf:/content"
      )
    end
  end
end
