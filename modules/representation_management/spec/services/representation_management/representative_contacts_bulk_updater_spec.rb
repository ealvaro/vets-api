# frozen_string_literal: true

require 'rails_helper'

RSpec.describe RepresentationManagement::RepresentativeContactsBulkUpdater do
  subject(:updater) { described_class.new }

  let(:csv_content) do
    <<~CSV
      Number,LastName,FirstName,MiddleName,WorkAddress1,WorkAddress2,WorkAddress3,WorkCity,WorkState,WorkZip,FaxNumber,WorkNumber,WorkEmailAddress,VeteranServiceOrganization
      102,Abel,Jami,Marie,105 Main Street,,,Painesville,OH,44077,,440-350-2591,jami.abel@example.gov,097 - Veterans of Foreign Wars
    CSV
  end
  let(:rows) { CSV.parse(csv_content, headers: true) }
  let(:fetcher) { instance_double(SensitiveRepoCsvFileFetcher, fetch: rows) }
  let(:response_body) { { 'updated' => 1, 'rejected' => [] } }
  let(:response) { instance_double(Faraday::Response, status: 200, body: response_body) }
  let(:posted_contacts) { [] }

  before do
    allow(SensitiveRepoCsvFileFetcher).to receive(:new).and_return(fetcher)
    allow(RepresentationManagement::GCLAWS::Client)
      .to receive(:post_representative_contacts) do |contacts:|
        posted_contacts.replace(contacts)
        response
      end
  end

  describe '#run' do
    context 'happy path' do
      it 'fetches, transforms, posts, and reports success' do
        expect(updater.run).to eq(success: true, submitted: 1, updated: 1, rejected: [])
      end

      it 'maps present CSV cells to the DTO' do
        updater.run

        contact = posted_contacts.first
        expect(contact[:number]).to eq('102')
        expect(contact[:lastName]).to eq('Abel')
        expect(contact[:workEmailAddress]).to eq('jami.abel@example.gov')
        expect(contact[:veteranServiceOrganization]).to eq('097 - Veterans of Foreign Wars')
      end

      it 'omits blank cells so existing upstream data is not clobbered' do
        updater.run

        contact = posted_contacts.first
        # WorkAddress2, WorkAddress3, and FaxNumber are blank in the CSV: they must be
        # absent from the payload, never sent as empty strings that overwrite good data.
        expect(contact).not_to have_key(:workAddress2)
        expect(contact).not_to have_key(:workAddress3)
        expect(contact).not_to have_key(:faxNumber)
        expect(contact.values).to all(be_present)
      end
    end

    context 'optional columns' do
      let(:csv_content) do
        <<~CSV
          Number,LastName,FirstName,WorkEmailAddress,Primary / Cross,Primary Accrediting Agency
          102,Abel,Jami,jami.abel@example.gov,Primary,Veterans of Foreign Wars
        CSV
      end

      it 'includes optional columns when present' do
        updater.run

        contact = posted_contacts.first
        expect(contact[:primaryCross]).to eq('Primary')
        expect(contact[:primaryAccreditation]).to eq('Veterans of Foreign Wars')
      end

      it 'omits optional columns when blank' do
        rows['Primary / Cross'] = nil
        updater.run

        expect(posted_contacts.first).not_to have_key(:primaryCross)
      end
    end

    context 'when a row is missing the required Number identity key' do
      let(:csv_content) do
        <<~CSV
          Number,LastName,FirstName,WorkEmailAddress
          ,Abel,Jami,jami.abel@example.gov
        CSV
      end

      it 'raises before posting anything upstream' do
        expect { updater.run }.to raise_error(/missing required field\(s\): number/)
        expect(RepresentationManagement::GCLAWS::Client).not_to have_received(:post_representative_contacts)
      end
    end

    context 'when the representative_contacts url is not configured' do
      before do
        allow(Settings.gclaws.accreditation).to receive(:representative_contacts).and_return(nil)
      end

      it 'raises a configuration error and does not fetch the CSV' do
        expect { updater.run }.to raise_error(/is not configured/)
        expect(SensitiveRepoCsvFileFetcher).not_to have_received(:new)
      end
    end

    context 'when the CSV cannot be fetched' do
      let(:fetcher) { instance_double(SensitiveRepoCsvFileFetcher, fetch: nil) }

      it 'raises a fetch error' do
        expect { updater.run }.to raise_error(/Failed to fetch CSV file/)
      end
    end

    context 'when the CSV is empty (headers only)' do
      let(:csv_content) { "Number,LastName,FirstName\n" }

      it 'raises an empty-file error' do
        expect { updater.run }.to raise_error(/CSV file is empty/)
      end
    end

    context 'when the API returns a 200 with partial rejections' do
      let(:response_body) do
        { 'updated' => 0, 'rejected' => [{ 'number' => '102', 'errorMessage' => 'Record not found' }] }
      end

      it 'reports the rejected records' do
        result = updater.run

        expect(result[:success]).to be(true)
        expect(result[:updated]).to eq(0)
        expect(result[:rejected]).to eq([{ 'number' => '102', 'errorMessage' => 'Record not found' }])
      end
    end

    context 'when the API returns a non-200 status with a hash body' do
      let(:response) { instance_double(Faraday::Response, status: 422, body: { 'errors' => 'Invalid payload' }) }

      it 'reports failure with the extracted error and status' do
        expect(updater.run).to eq(success: false, error: 'Invalid payload', status: 422)
      end
    end

    context 'when the API returns a non-200 status with a non-hash body' do
      let(:response) { instance_double(Faraday::Response, status: 503, body: 'Service Unavailable') }

      it 'passes the raw body through as the error' do
        expect(updater.run).to eq(success: false, error: 'Service Unavailable', status: 503)
      end
    end
  end
end
