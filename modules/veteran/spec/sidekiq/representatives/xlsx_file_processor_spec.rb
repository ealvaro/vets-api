# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Representatives::XlsxFileProcessor do
  let(:mock_file_content) { File.read('modules/veteran/spec/fixtures/xlsx_files/rep-mock-data.xlsx') }
  let(:xlsx_processor) { described_class.new(mock_file_content) }

  def check_values(hash)
    invalid_values = ['', 'null']

    hash.each do |key, value|
      if value.is_a?(String)
        expect(invalid_values).not_to include(value.downcase)
        expect(value).to match(/\A[\w+\-.]+@[a-z\d\-.]+\.[a-z]+\z/i) if key == 'email_address'
      elsif value.is_a?(Hash)
        check_values(value)
      end
    end
  end

  describe '#process' do
    let(:result) { xlsx_processor.process }

    context 'with valid data' do
      let(:expected_keys) { %i[id address email phone_number raw_address] }
      let(:expected_address_keys) do
        %i[address_pou address_line1 address_line2 address_line3 city state zip_code5 zip_code4
           country_code_iso3]
      end
      let(:expected_raw_address_keys) { %w[address_line1 address_line2 address_line3 city state_code zip_code] }

      it 'processes the file and validates the data structure and content' do
        expect(result).to be_a(Hash)
        expect(result.keys).to include('Agents', 'Attorneys', 'Representatives')

        result.each_value do |value_array|
          expect(value_array).to all(be_a(Hash))

          value_array.each do |row|
            expect(row.keys).to match_array(expected_keys)
            expect(row[:address].keys).to match_array(expected_address_keys)
            expect(row[:raw_address].keys).to match_array(expected_raw_address_keys)
            check_values(row)
          end
        end
      end

      it 'includes raw_address with string keys matching AccreditedIndividual pattern' do
        result.each_value do |value_array|
          value_array.each do |row|
            raw_address = row[:raw_address]
            expect(raw_address).to be_a(Hash)
            expect(raw_address.keys).to all(be_a(String))
            expect(raw_address['address_line1']).to eq(row[:address][:address_line1])
            expect(raw_address['city']).to eq(row[:address][:city])
            expect(raw_address['state_code']).to eq(row[:address][:state][:state_code])
          end
        end
      end

      it 'formats zip_code correctly in raw_address without zip4' do
        row_without_zip4 = result['Agents'].find { |r| r[:address][:zip_code4].nil? }
        expect(row_without_zip4).to be_present, 'Fixture data should include at least one row without zip_code4'

        expect(row_without_zip4[:raw_address]['zip_code']).to eq(row_without_zip4[:address][:zip_code5])
      end

      it 'deduplicates the rows based on the "Number" column' do
        # There are no duplicate "Number" values in the Agents and Attorneys sheets
        expect(result['Agents'].count).to eq(5)
        expect(result['Attorneys'].count).to eq(5)
        # There are 19 rows of data in the Representatives sheet, but 12 of them have duplicate "Number" values
        expect(result['Representatives'].count).to eq(7)
      end
    end

    context 'when an error occurs opening the spreadsheet' do
      let(:invalid_file_content) { 'invalid content' }
      let(:xlsx_processor) { described_class.new(invalid_file_content) }
      let(:error_message) { 'Mocked Roo error' }

      before do
        allow(Roo::Spreadsheet).to receive(:open).and_raise(Roo::Error.new(error_message))
        allow(xlsx_processor).to receive(:log_error)
      end

      it 'logs the error when opening the spreadsheet fails' do
        expect { xlsx_processor.process }.not_to raise_error
        expected_log_message = "Error opening spreadsheet: #{error_message}"
        expect(xlsx_processor).to have_received(:log_error).with(expected_log_message)
      end
    end

    context 'when an error occurs during processing' do
      let(:error_message) { 'test error' }

      before do
        allow(Roo::Spreadsheet).to receive(:open).and_raise(StandardError.new(error_message))
        allow(Rails.logger).to receive(:error)
      end

      it 'rescues the error and logs it to Rails.logger.error' do
        expect { xlsx_processor.process }.not_to raise_error
        expected_log_message = "XlsxFileProcessor error: Error processing XLSX file: #{error_message}"
        expect(Rails.logger).to have_received(:error).with(expected_log_message)
      end
    end

    context 'with state code validation' do
      it 'processes only US-state rows with full address data' do
        valid_states = Representatives::XlsxFileProcessor::US_STATES_TERRITORIES.keys

        result.each_value do |value_array|
          value_array.each do |row|
            next if row[:address].nil? # Skip contact-only rows

            state_code = row.dig(:address, :state, :state_code)
            expect(valid_states).to include(state_code) unless state_code.nil?
          end
        end
      end
    end

    context 'with foreign state codes' do
      let(:header_row) do
        %w[Number FirstName LastName WorkAddress1 WorkAddress2
           WorkAddress3 WorkCity WorkState WorkZip WorkNumber
           WorkEmailAddress]
      end
      let(:us_row) do
        ['111', 'Jane', 'Doe', '123 Main St', nil, nil,
         'Arlington', 'VA', '22201', '703-555-1234', 'jane@example.com']
      end
      let(:foreign_row_with_email) do
        ['222', 'Hans', 'Mueller', 'Berliner Str 1', nil, nil,
         'Berlin', 'BE', '10115', '030-555-1234', 'hans@example.de']
      end
      let(:foreign_row_no_contact) do
        ['333', 'Pierre', 'Dupont', 'Rue de Rivoli 1', nil, nil,
         'Paris', 'FR', '75001', nil, nil]
      end
      let(:foreign_row_phone_only) do
        ['444', 'Yuki', 'Tanaka', 'Shibuya 1-1', nil, nil,
         'Tokyo', 'TK', '150-0002', '03-1234-5678', nil]
      end
      let(:mock_sheet) do
        sheet = double('sheet')
        allow(sheet).to receive(:row).with(1).and_return(header_row)
        allow(sheet).to receive(:each_with_index)
          .and_yield(header_row, 0)
          .and_yield(us_row, 1)
          .and_yield(foreign_row_with_email, 2)
          .and_yield(foreign_row_no_contact, 3)
          .and_yield(foreign_row_phone_only, 4)
        sheet
      end
      let(:mock_xlsx) do
        xlsx = double('xlsx')
        allow(xlsx).to receive(:sheet).and_return(mock_sheet)
        xlsx
      end
      let(:result) { described_class.new('').process }

      before do
        allow(Roo::Spreadsheet).to receive(:open).and_return(mock_xlsx)
      end

      it 'includes foreign rows with valid email as contact-only data' do
        reps = result['Representatives']
        foreign_rep = reps.find { |r| r[:id] == '222' }

        expect(foreign_rep).to be_present
        expect(foreign_rep[:email]).to eq('hans@example.de')
        expect(foreign_rep[:phone_number]).to eq('030-555-1234')
        expect(foreign_rep[:address]).to be_nil
        expect(foreign_rep[:raw_address]).to be_nil
      end

      it 'includes US rows with full address data' do
        reps = result['Representatives']
        us_rep = reps.find { |r| r[:id] == '111' }

        expect(us_rep).to be_present
        expect(us_rep[:email]).to eq('jane@example.com')
        expect(us_rep[:address]).to be_present
        expect(us_rep[:raw_address]).to be_present
      end

      it 'excludes foreign rows with no email or phone' do
        reps = result['Representatives']
        no_contact_rep = reps.find { |r| r[:id] == '333' }

        expect(no_contact_rep).to be_nil
      end

      it 'includes foreign rows with phone only' do
        reps = result['Representatives']
        phone_only_rep = reps.find { |r| r[:id] == '444' }

        expect(phone_only_rep).to be_present
        expect(phone_only_rep[:email]).to be_nil
        expect(phone_only_rep[:phone_number]).to eq('03-1234-5678')
        expect(phone_only_rep[:address]).to be_nil
      end
    end
  end

  describe '#format_raw_zip' do
    subject(:processor) { described_class.new('') }

    it 'formats zip_code correctly with zip4' do
      result = processor.send(:format_raw_zip, '12345', '6789')
      expect(result).to eq('12345-6789')
    end

    it 'formats zip_code correctly without zip4' do
      result = processor.send(:format_raw_zip, '12345', nil)
      expect(result).to eq('12345')
    end

    it 'returns nil when zip5 is blank' do
      expect(processor.send(:format_raw_zip, nil, nil)).to be_nil
      expect(processor.send(:format_raw_zip, '', nil)).to be_nil
    end
  end
end
