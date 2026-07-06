# frozen_string_literal: true

require 'rails_helper'
require SimpleFormsApi::Engine.root.join(
  'app', 'services', 'simple_forms_api', 'mms', 'vba_10_8678_ibm_converter'
)

RSpec.describe SimpleFormsApi::Mms::VBA108678IbmConverter do
  let(:fixture_dir) { SimpleFormsApi::Engine.root.join('spec', 'fixtures', 'form_json') }
  let(:form) { instance_double(SimpleFormsApi::VBA108678, data:) }

  let(:device_list) do
    [
      {
        device: 'Hearing Aid',
        disability: 'Hearing Loss',
        impacted_locations: {
          upper_left: true,
          upper_right: false,
          lower_left: false,
          lower_right: false
        }
      },
      {
        device: 'Prosthetic Leg',
        disability: 'Amputation',
        impacted_locations: {
          upper_left: false,
          upper_right: true,
          lower_left: false,
          lower_right: false
        }
      },
      {
        device: 'Thing 3',
        disability: 'device 3',
        impacted_locations: {
          upper_left: false,
          upper_right: false,
          lower_left: true,
          lower_right: false
        }
      },
      {
        device: 'thing 4',
        disability: 'device 4',
        impacted_locations: {
          upper_left: false,
          upper_right: false,
          lower_left: false,
          lower_right: true
        }
      }
    ]
  end

  before do
    allow(form).to receive(:appliances_for_pdf).and_return(device_list)
  end

  describe '.convert' do
    context 'with the existing 10-8678 fixture' do
      let(:data) { JSON.parse(File.read(fixture_dir.join('vba_10_8678.json'))) }
      let(:expected) { JSON.parse(File.read(fixture_dir.join('vba_10_8678_ibm_payload.json'))) }

      it 'produces the expected MMS payload' do
        expect(described_class.convert(form)).to eq(expected)
      end

      it 'returns keys sorted alphabetically' do
        keys = described_class.convert(form).keys
        expect(keys).to eq(keys.sort)
      end

      it 'emits exactly the 39 fields defined in the data dictionary' do
        expect(described_class.convert(form).size).to eq(39)
      end
    end
  end

  describe 'field-level transformations' do
    let(:data) do
      {
        'full_name' => { 'first' => 'John', 'middle' => 'D', 'last' => 'Doe' },
        'ssn' => '123456789',
        'address' => {
          'street' => '123 Main St',
          'street2' => 'Apt 4B',
          'city' => 'Springfield',
          'state' => 'PA',
          'postal_code' => '22150',
          'country' => 'USA'
        },
        'phone' => '7035551234',
        'email_address' => 'john.doe@example.com',
        'veteran_signature' => 'John A Doe',
        'signature_date' => '2026-04-16',
        'appliances' => []
      }
    end

    it 'formats the veteran name as LAST, FIRST, MIDDLE' do
      expect(described_class.convert(form)['VETERAN_NAME']).to eq('Doe, John, D')
    end

    it 'converts ISO signature dates to MM/DD/YYYY' do
      expect(described_class.convert(form)['DATE_OF_VETERAN_SIGNATURE']).to eq('04/16/2026')
    end

    it 'flattens the address block with city/state ZIP and country' do
      expect(described_class.convert(form)['VETERAN_ADDRESS_FULL_BLOCK']).to eq(
        "123 Main St Apt 4B\nSpringfield, PA 22150\nUSA"
      )
    end

    it 'sets VETERAN_SIGNATURE to "1" when veteranSignature is present' do
      expect(described_class.convert(form)['VETERAN_SIGNATURE']).to eq(1)
    end

    context 'when veteranSignature is blank' do
      before { data['veteran_signature'] = '' }

      it 'sets VETERAN_SIGNATURE to "0"' do
        expect(described_class.convert(form)['VETERAN_SIGNATURE']).to eq(0)
      end
    end
  end

  describe 'helper behavior' do
    let(:data) { {} }

    describe '.normalize_last_4_ssn' do
      it 'strips dashes and non-digits' do
        expect(described_class.normalize_last_4_ssn('123-45-6789')).to eq('6789')
      end

      it 'returns empty string for nil' do
        expect(described_class.normalize_last_4_ssn(nil)).to eq('')
      end
    end

    describe '.phone_digits' do
      it 'strips formatting from a string phone' do
        expect(described_class.phone_digits('(703) 555-1234')).to eq('7035551234')
      end

      it 'handles a hash with areaCode and number' do
        expect(described_class.phone_digits('area_code' => '703', 'number' => '5551234'))
          .to eq('7035551234')
      end

      it 'returns empty string for nil' do
        expect(described_class.phone_digits(nil)).to eq('')
      end
    end

    describe '.format_iso_date' do
      it 'formats ISO 8601 dates as MM/DD/YYYY' do
        expect(described_class.format_iso_date('2026-04-16')).to eq('04/16/2026')
      end

      it 'returns empty string for nil' do
        expect(described_class.format_iso_date(nil)).to eq('')
      end

      it 'returns empty string for unparseable input' do
        expect(described_class.format_iso_date('not a date')).to eq('')
      end

      it 'handles {month, day, year} hashes for forward compat' do
        expect(described_class.format_iso_date('month' => '4', 'day' => '16', 'year' => '2026'))
          .to eq('04/16/2026')
      end
    end
  end

  describe 'edge cases' do
    context 'when the appliances array has more than 4 entries' do
      let(:data) do
        {
          'appliances' => Array.new(7) { |i| { 'device_or_medication' => "Appliance #{i + 1}" } }
        }
      end

      it 'truncates to 4' do
        result = described_class.convert(form)
        expect(result['NAME_APPLIANCE_4']).to eq('thing 4')
        expect(result.keys).not_to include('NAME_APPLIANCE_5')
      end
    end
  end
end
