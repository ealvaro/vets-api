# frozen_string_literal: true

require 'rails_helper'

RSpec.describe RepresentationManagement::XlsxFileProcessor do
  let(:fixture_path) { 'modules/representation_management/spec/fixtures/xlsx_files/rep-mock-data.xlsx' }
  let(:mock_file_content) { File.read(fixture_path) }

  describe '#process' do
    context 'with all types' do
      subject { described_class.new(mock_file_content) }

      let(:result) { subject.process }

      it 'processes all sheets' do
        expect(result.keys).to match_array(%w[attorney claims_agent representative organization])
      end

      it 'returns a hash' do
        expect(result).to be_a(Hash)
      end
    end

    context 'with filtered types' do
      subject { described_class.new(mock_file_content, ['attorney']) }

      let(:result) { subject.process }

      it 'only processes specified types' do
        expect(result.keys).to eq(['attorney'])
        expect(result).not_to have_key('organization')
        expect(result).not_to have_key('claims_agent')
        expect(result).not_to have_key('representative')
      end
    end

    context 'individual sheet processing' do
      subject { described_class.new(mock_file_content, ['attorney']) }

      let(:result) { subject.process }
      let(:expected_keys) { %i[ogc_id registration_number individual_type email phone_number address raw_address] }

      it 'returns records with required keys' do
        attorneys = result['attorney']
        expect(attorneys).to be_present

        attorneys.each do |record|
          expect(record.keys).to match_array(expected_keys)
        end
      end

      it 'sets individual_type correctly' do
        result['attorney'].each do |record|
          expect(record[:individual_type]).to eq('attorney')
        end
      end

      it 'includes ogc_id as a UUID' do
        result['attorney'].each do |record|
          expect(record[:ogc_id]).to match(/\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/i)
        end
      end

      it 'builds raw_address with string keys' do
        result['attorney'].each do |record|
          raw_address = record[:raw_address]
          expect(raw_address).to be_a(Hash)
          expect(raw_address.keys).to all(be_a(String))
          expect(raw_address).to have_key('address_line1')
          expect(raw_address).to have_key('city')
          expect(raw_address).to have_key('state_code')
          expect(raw_address).to have_key('zip_code')
        end
      end

      it 'includes address with expected structure' do
        expected_address_keys = %i[address_pou address_line1 address_line2 address_line3
                                   city state zip_code5 zip_code4 country_code_iso3]

        result['attorney'].each do |record|
          expect(record[:address].keys).to match_array(expected_address_keys)
          expect(record[:address][:address_pou]).to eq('RESIDENCE')
          expect(record[:address][:country_code_iso3]).to eq('US')
        end
      end
    end

    context 'claims agent processing' do
      subject { described_class.new(mock_file_content, ['claims_agent']) }

      let(:result) { subject.process }

      it 'processes the Agents sheet' do
        agents = result['claims_agent']
        expect(agents).to be_present
      end

      it 'sets individual_type to claims_agent' do
        result['claims_agent'].each do |record|
          expect(record[:individual_type]).to eq('claims_agent')
        end
      end
    end

    context 'representative processing' do
      subject { described_class.new(mock_file_content, ['representative']) }

      let(:result) { subject.process }

      it 'processes the Representatives sheet' do
        reps = result['representative']
        expect(reps).to be_present
      end

      it 'sets individual_type to representative' do
        result['representative'].each do |record|
          expect(record[:individual_type]).to eq('representative')
        end
      end
    end

    context 'organization sheet processing' do
      subject { described_class.new(mock_file_content, ['organization']) }

      let(:result) { subject.process }
      let(:expected_keys) { %i[ogc_id poa_code name phone address raw_address] }

      it 'returns records with required keys' do
        orgs = result['organization']
        expect(orgs).to be_present

        orgs.each do |record|
          expect(record.keys).to match_array(expected_keys)
        end
      end

      it 'builds raw_address with string keys' do
        result['organization'].each do |record|
          raw_address = record[:raw_address]
          expect(raw_address).to be_a(Hash)
          expect(raw_address.keys).to all(be_a(String))
        end
      end

      it 'includes address with CORRESPONDENCE pou' do
        result['organization'].each do |record|
          expect(record[:address][:address_pou]).to eq('CORRESPONDENCE')
        end
      end

      it 'includes ogc_id as a UUID' do
        result['organization'].each do |record|
          expect(record[:ogc_id]).to match(/\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/i)
        end
      end
    end

    context 'US state filtering' do
      subject { described_class.new(mock_file_content) }

      let(:result) { subject.process }

      it 'only includes records from US states and territories' do
        result.each_value do |records|
          records.each do |record|
            state = record.dig(:raw_address, 'state_code')
            next unless state

            expect(described_class::US_STATES_TERRITORIES).to have_key(state)
          end
        end
      end
    end

    context 'deduplication' do
      subject { described_class.new(mock_file_content, ['representative']) }

      let(:result) { subject.process }

      it 'deduplicates individual records by registration number' do
        reps = result['representative']
        registration_numbers = reps.map { |r| r[:registration_number] }
        expect(registration_numbers).to eq(registration_numbers.uniq)
      end
    end

    context 'organization deduplication' do
      subject { described_class.new(mock_file_content, ['organization']) }

      let(:result) { subject.process }

      it 'deduplicates organization records by poa_code' do
        orgs = result['organization']
        poa_codes = orgs.map { |r| r[:poa_code] }
        expect(poa_codes).to eq(poa_codes.uniq)
      end
    end

    context 'with invalid file content' do
      subject { described_class.new('not a valid xlsx file') }

      it 'returns empty hash on error' do
        result = subject.process
        expect(result).to eq({})
      end

      it 'logs the error' do
        expect(Rails.logger).to receive(:error).with(/XlsxFileProcessor error/)
        subject.process
      end
    end

    context 'zip code formatting' do
      subject { described_class.new(mock_file_content, ['attorney']) }

      let(:result) { subject.process }

      it 'formats zip codes correctly' do
        result['attorney'].each do |record|
          zip = record.dig(:raw_address, 'zip_code')
          next unless zip

          if zip.include?('-')
            zip5, zip4 = zip.split('-')
            expect(zip5.length).to eq(5)
            expect(zip4.length).to eq(4)
          else
            expect(zip.length).to eq(5)
          end
        end
      end
    end

    context 'email validation' do
      subject { described_class.new(mock_file_content, ['attorney']) }

      let(:result) { subject.process }

      it 'only includes valid emails' do
        result['attorney'].each do |record|
          next unless record[:email]

          expect(record[:email]).to match(/\A[\w+\-.]+@[a-z\d\-.]+\.[a-z]+\z/i)
        end
      end
    end

    context 'null value handling' do
      subject { described_class.new(mock_file_content) }

      let(:result) { subject.process }

      it 'converts blank and null strings to nil' do
        result.each_value do |records|
          records.each do |record|
            record.each_value do |value|
              next unless value.is_a?(String)

              expect(value.downcase).not_to eq('null')
              expect(value).not_to be_empty
            end
          end
        end
      end
    end

    context 'when an error occurs opening the spreadsheet' do
      let(:error_message) { 'Mocked Roo error' }

      before do
        allow(Roo::Spreadsheet).to receive(:open).and_raise(Roo::Error.new(error_message))
      end

      it 'handles the error gracefully' do
        processor = described_class.new('some content')
        result = processor.process
        expect(result).to eq({})
      end
    end

    context 'foreign state codes for individuals' do
      let(:header_row) do
        %w[Number FirstName LastName WorkAddress1 WorkAddress2
           WorkAddress3 WorkCity WorkState WorkZip WorkNumber
           EmailAddress AccrAttorneyId]
      end
      let(:us_row) do
        ['111', 'Jane', 'Doe', '123 Main St', nil, nil,
         'Arlington', 'VA', '22201', '703-555-1234',
         'jane@example.com', 'att-uuid-1']
      end
      let(:foreign_row_with_email) do
        ['222', 'Hans', 'Mueller', 'Berliner Str 1', nil, nil,
         'Berlin', 'BE', '10115', '030-555-1234',
         'hans@example.de', 'att-uuid-2']
      end
      let(:foreign_row_no_contact) do
        ['333', 'Pierre', 'Dupont', 'Rue de Rivoli', nil, nil,
         'Paris', 'FR', '75001', nil, nil, 'att-uuid-3']
      end
      let(:mock_sheet) do
        sheet = double('sheet')
        allow(sheet).to receive(:row).with(1).and_return(header_row)
        allow(sheet).to receive(:each_with_index)
          .and_yield(header_row, 0)
          .and_yield(us_row, 1)
          .and_yield(foreign_row_with_email, 2)
          .and_yield(foreign_row_no_contact, 3)
        sheet
      end
      let(:mock_xlsx) do
        xlsx = double('xlsx')
        allow(xlsx).to receive(:sheet).and_return(mock_sheet)
        xlsx
      end
      let(:result) { described_class.new('', ['attorney']).process }

      before do
        allow(Roo::Spreadsheet).to receive(:open).and_return(mock_xlsx)
      end

      it 'includes foreign rows with email as contact-only data' do
        attorneys = result['attorney']
        foreign = attorneys.find { |r| r[:registration_number] == '222' }

        expect(foreign).to be_present
        expect(foreign[:email]).to eq('hans@example.de')
        expect(foreign[:address]).to be_nil
        expect(foreign[:raw_address]).to be_nil
      end

      it 'includes US rows with full address data' do
        attorneys = result['attorney']
        us_rep = attorneys.find { |r| r[:registration_number] == '111' }

        expect(us_rep).to be_present
        expect(us_rep[:address]).to be_present
        expect(us_rep[:raw_address]).to be_present
      end

      it 'excludes foreign rows with no email or phone' do
        attorneys = result['attorney']
        no_contact = attorneys.find { |r| r[:registration_number] == '333' }

        expect(no_contact).to be_nil
      end
    end

    context 'foreign state codes for organizations' do
      let(:header_row) do
        %w[POA OrganizationName OrganizationAddressLine1
           OrganizationAddressLine2 OrganizationAddressLine3
           OrganizationCity OrganizationState
           OrganizationZipCode OrganizationPhoneNumber VSOID]
      end
      let(:us_org) do
        ['A01', 'US Org', '123 Main St', nil, nil,
         'DC', 'DC', '20001', '202-555-1234', 'org-uuid-1']
      end
      let(:foreign_org_with_phone) do
        ['B02', 'Foreign Org', 'Berliner Str', nil, nil,
         'Berlin', 'BE', '10115', '030-555-1234', 'org-uuid-2']
      end
      let(:foreign_org_no_phone) do
        ['C03', 'No Phone Org', 'Rue de Rivoli', nil, nil,
         'Paris', 'FR', '75001', nil, 'org-uuid-3']
      end
      let(:mock_sheet) do
        sheet = double('sheet')
        allow(sheet).to receive(:row).with(1).and_return(header_row)
        allow(sheet).to receive(:each_with_index)
          .and_yield(header_row, 0)
          .and_yield(us_org, 1)
          .and_yield(foreign_org_with_phone, 2)
          .and_yield(foreign_org_no_phone, 3)
        sheet
      end
      let(:mock_xlsx) do
        xlsx = double('xlsx')
        allow(xlsx).to receive(:sheet).and_return(mock_sheet)
        xlsx
      end
      let(:result) { described_class.new('', ['organization']).process }

      before do
        allow(Roo::Spreadsheet).to receive(:open).and_return(mock_xlsx)
      end

      it 'includes foreign orgs with phone as contact-only data' do
        orgs = result['organization']
        foreign = orgs.find { |r| r[:poa_code] == 'B02' }

        expect(foreign).to be_present
        expect(foreign[:phone]).to eq('030-555-1234')
        expect(foreign[:address]).to be_nil
        expect(foreign[:raw_address]).to be_nil
      end

      it 'excludes foreign orgs with no phone' do
        orgs = result['organization']
        no_phone = orgs.find { |r| r[:poa_code] == 'C03' }

        expect(no_phone).to be_nil
      end
    end
  end
end
