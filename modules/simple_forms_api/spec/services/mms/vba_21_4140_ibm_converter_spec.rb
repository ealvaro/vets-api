# frozen_string_literal: true

# spec/services/mss/form4140_ibm_converter_spec.rb
require 'rails_helper'

require SimpleFormsApi::Engine.root.join('spec', 'spec_helper.rb')

RSpec.describe SimpleFormsApi::Mms::VBA214140IbmConverter do
  let(:fixture_file) { 'vba_21_4140.json' }
  let(:min_file) { 'vba_21_4140-min.json' }
  let(:fixture_path) do
    Rails.root.join('modules', 'simple_forms_api', 'spec', 'fixtures', 'form_json', fixture_file)
  end
  let(:min_example_path) do
    Rails.root.join('modules', 'simple_forms_api', 'spec', 'fixtures', 'form_json', min_file)
  end
  let(:data) { JSON.parse(File.read(fixture_path)) }
  let(:form) { SimpleFormsApi::VBA214140.new(data) }

  let(:ibm_fixture_file) { 'vba_21_4140_ibm_payload.json' }
  let(:ibm_fixture_path) do
    Rails.root.join('modules', 'simple_forms_api', 'spec', 'fixtures', 'form_json', ibm_fixture_file)
  end
  let(:ibm_payload) { JSON.parse(File.read(ibm_fixture_path)) }

  describe '#convert' do
    subject(:payload) { described_class.convert(form) }

    it 'converts a parsed form to the keys and formats expected by IBM' do
      Timecop.freeze(Time.zone.yesterday) do
        ibm_payload['DATE_SIGNED'] = Time.zone.yesterday.strftime('%m/%d/%Y')

        expect(payload).to eq(ibm_payload)
      end
    end

    it 'uses blank string for missing data' do
      min_form = JSON.parse(File.read(min_example_path))
      form = SimpleFormsApi::VBA214140.new(min_form)
      ibm_payload = described_class.convert(form)
      expect(ibm_payload['EMPLOYER_NAME_ADDRESS']).to eq('')
      expect(ibm_payload['EMPLOYER_NAME_ADDRESS1']).to eq('')
      expect(ibm_payload['EMPLOYER_NAME_ADDRESS2']).to eq('')
      expect(ibm_payload['EMPLOYER_NAME_ADDRESS3']).to eq('')
      expect(ibm_payload['PHONE_NUMBER']).to eq('')
      expect(ibm_payload['VA_FILE_NUMBER']).to eq('')
      expect(ibm_payload['VETERAN_ADDRESS_LINE2']).to eq('')
      expect(ibm_payload['VETERAN_DOB']).to eq('')
      expect(ibm_payload['VETERAN_SSN']).to eq('')
    end

    it 'normalizes SSN' do
      expect(payload['VETERAN_SSN']).to eq('547901234')
    end

    it 'formats DOB as MMDDYYYY' do
      expect(payload['VETERAN_DOB']).to eq('02/27/1979')
    end

    it 'downcases email' do
      expect(payload['EMAIL']).to eq('test@example.com')
    end

    it 'includes employer info' do
      expect(payload['EMPLOYER_NAME_ADDRESS'])
        .to eq('Test Employer\\n1234 Executive Ave\\nMetropolis, CA 90210\\nUnited States of America')
    end

    it 'includes full name correctly' do
      expect(payload['VETERAN_NAME']).to eq('Rumpelstilts T Mephistopheles-Rei')
    end

    it 'truncates first name correctly' do
      expect(payload['VETERAN_FIRST_NAME']).to eq('Rumpelstilts')
    end

    it 'sets DATE_SIGNED as the current date' do
      Timecop.freeze(Time.zone.yesterday) do
        expect(payload['DATE_SIGNED'])
          .to eq(Time.zone.yesterday.strftime('%m/%d/%Y'))
      end
    end
  end
end
