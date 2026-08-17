# frozen_string_literal: true

require 'rails_helper'
require 'faraday'
require 'json'

RSpec.describe RepresentationManagement::GCLAWS::Client do
  subject { described_class }

  before do
    # Mock the Slack client instead of the subject method
    slack_client = instance_double(SlackNotify::Client)
    allow(SlackNotify::Client).to receive(:new).and_return(slack_client)
    allow(slack_client).to receive(:notify)
  end

  let(:error_string_prefix) { 'RepresentationManagement::GCLAWS::Client error: GCLAWS Accreditation API' }

  describe '.get_accredited_entities' do
    context 'when the type is invalid' do
      let(:type) { 'invalid' }

      it 'returns an empty hash' do
        response = subject.get_accredited_entities(type:)
        expect(response).to eq({})
      end
    end

    context 'when the type is valid' do
      let(:type) { 'agents' }
      let(:parsed_body) { { field: 'value' } }

      context 'when the request is successful' do
        it 'returns a successful response' do
          stub_request(:get, Settings.gclaws.accreditation.agents.url)
            .with(query: { 'page' => 1, 'pageSize' => 1000, 'sortColumn' => 'LastName', 'sortOrder' => 'ASC' })
            .to_return(status: 200, body: parsed_body.to_json, headers: { 'Content-Type' => 'application/json' })

          response = subject.get_accredited_entities(type:)

          expect(response.status).to eq(200)
          expect(response.body).to eq(parsed_body.stringify_keys)
        end
      end

      context 'when the request is unauthorized' do
        it 'logs the error and returns an unauthorized status' do
          stub_request(:get, Settings.gclaws.accreditation.agents.url)
            .with(query: { 'page' => 1, 'pageSize' => 1000, 'sortColumn' => 'LastName', 'sortOrder' => 'ASC' })
            .to_raise(Faraday::UnauthorizedError.new('GCLAWS Accreditation unauthorized'))

          expect(Rails.logger).to receive(:error).with(
            "#{error_string_prefix} unauthorized error for #{type}: GCLAWS Accreditation unauthorized"
          )

          response = subject.get_accredited_entities(type:)

          expect(response.status).to eq(:unauthorized)
          expect(response.body['errors']).to eq('GCLAWS Accreditation unauthorized')
          expect(response.body['items']).to eq([])
          expect(response.body['totalRecords']).to eq(0)
        end
      end

      context 'when the connection fails' do
        it 'logs the error and returns a service unavailable status' do
          stub_request(:get, Settings.gclaws.accreditation.agents.url)
            .with(query: { 'page' => 1, 'pageSize' => 1000, 'sortColumn' => 'LastName', 'sortOrder' => 'ASC' })
            .to_raise(Faraday::ConnectionFailed.new('GCLAWS Accreditation unavailable'))

          expect(Rails.logger).to receive(:error).with(
            "#{error_string_prefix} connection_failed error for #{type}: GCLAWS Accreditation unavailable"
          )

          response = subject.get_accredited_entities(type:)

          expect(response.status).to eq(:service_unavailable)
          expect(response.body['errors']).to eq('GCLAWS Accreditation unavailable')
          expect(response.body['items']).to eq([])
          expect(response.body['totalRecords']).to eq(0)
        end
      end

      context 'when the request times out' do
        it 'logs the error and returns a request timeout status' do
          stub_request(:get, Settings.gclaws.accreditation.agents.url)
            .with(query: { 'page' => 1, 'pageSize' => 1000, 'sortColumn' => 'LastName', 'sortOrder' => 'ASC' })
            .to_raise(Faraday::TimeoutError.new('GCLAWS Accreditation request timed out'))

          expect(Rails.logger).to receive(:error).with(
            "#{error_string_prefix} timeout error for #{type}: GCLAWS Accreditation request timed out"
          )

          response = subject.get_accredited_entities(type:)

          expect(response.status).to eq(:request_timeout)
          expect(response.body['errors']).to eq('GCLAWS Accreditation request timed out')
          expect(response.body['items']).to eq([])
          expect(response.body['totalRecords']).to eq(0)
        end
      end
    end
  end

  describe '.post_representative_contacts' do
    let(:representative_contacts_url) { Settings.gclaws.accreditation.representative_contacts.url }
    let(:contacts) do
      [
        {
          number: '102',
          lastName: 'Abel',
          firstName: 'Jami',
          middleName: 'Marie',
          workAddress1: '105 Main Street',
          workAddress2: 'PO Box 490',
          workAddress3: '',
          workCity: 'Painesville',
          workState: 'OH',
          workZip: '44077',
          faxNumber: '',
          workNumber: '440-350-2591',
          workEmailAddress: 'jami.abel@lakecountyohio.gov',
          veteranServiceOrganization: '097 - Veterans of Foreign Wars'
        }
      ]
    end

    let(:error_string_prefix) { 'RepresentationManagement::GCLAWS::Client error: GCLAWS Accreditation API' }

    context 'when contacts is blank' do
      it 'returns a bad request error response' do
        response = subject.post_representative_contacts(contacts: [])

        expect(response.status).to eq(:bad_request)
        expect(response.body['errors']).to eq('No contacts provided')
      end
    end

    context 'when the request is successful with all records accepted' do
      it 'returns a response with updated count and empty rejected array' do
        stub_request(:post, representative_contacts_url)
          .to_return(
            status: 200,
            body: { 'updated' => 1, 'rejected' => [] }.to_json,
            headers: { 'Content-Type' => 'application/json' }
          )

        response = subject.post_representative_contacts(contacts:)

        expect(response.status).to eq(200)
        expect(response.body['updated']).to eq(1)
        expect(response.body['rejected']).to eq([])
      end
    end

    context 'when the request is successful with partial rejections' do
      it 'returns a response with updated count and rejected records' do
        rejected = [{ 'number' => '999', 'errorMessage' => 'Record not found' }]
        stub_request(:post, representative_contacts_url)
          .to_return(
            status: 200,
            body: { 'updated' => 1, 'rejected' => rejected }.to_json,
            headers: { 'Content-Type' => 'application/json' }
          )

        response = subject.post_representative_contacts(contacts:)

        expect(response.status).to eq(200)
        expect(response.body['updated']).to eq(1)
        expect(response.body['rejected']).to eq(rejected)
      end
    end

    context 'when the request is unauthorized' do
      it 'logs the error and returns an unauthorized status' do
        stub_request(:post, representative_contacts_url)
          .to_raise(Faraday::UnauthorizedError.new('GCLAWS RepresentativeContacts unauthorized'))

        expect(Rails.logger).to receive(:error).with(
          "#{error_string_prefix} unauthorized error for representative_contacts: " \
          'GCLAWS RepresentativeContacts unauthorized'
        )

        response = subject.post_representative_contacts(contacts:)

        expect(response.status).to eq(:unauthorized)
        expect(response.body['errors']).to eq('GCLAWS RepresentativeContacts unauthorized')
      end
    end

    context 'when the connection fails' do
      it 'logs the error and returns a service unavailable status' do
        stub_request(:post, representative_contacts_url)
          .to_raise(Faraday::ConnectionFailed.new('GCLAWS RepresentativeContacts unavailable'))

        expect(Rails.logger).to receive(:error).with(
          "#{error_string_prefix} connection_failed error for representative_contacts: " \
          'GCLAWS RepresentativeContacts unavailable'
        )

        response = subject.post_representative_contacts(contacts:)

        expect(response.status).to eq(:service_unavailable)
        expect(response.body['errors']).to eq('GCLAWS RepresentativeContacts unavailable')
      end
    end

    context 'when the request times out' do
      it 'logs the error and returns a request timeout status' do
        stub_request(:post, representative_contacts_url)
          .to_raise(Faraday::TimeoutError.new('GCLAWS RepresentativeContacts request timed out'))

        expect(Rails.logger).to receive(:error).with(
          "#{error_string_prefix} timeout error for representative_contacts: " \
          'GCLAWS RepresentativeContacts request timed out'
        )

        response = subject.post_representative_contacts(contacts:)

        expect(response.status).to eq(:request_timeout)
        expect(response.body['errors']).to eq('GCLAWS RepresentativeContacts request timed out')
      end
    end
  end
end
