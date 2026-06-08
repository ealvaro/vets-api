# frozen_string_literal: true

require 'rails_helper'
require SimpleFormsApi::Engine.root.join(
  'app', 'services', 'simple_forms_api', 'mms', 'vba_10_8678_ibm_converter'
)

RSpec.describe SimpleFormsApi::Mms::VBA108678IbmConverter do
  let(:fixture_dir) { SimpleFormsApi::Engine.root.join('spec', 'fixtures', 'form_json') }

  let(:form) { instance_double(SimpleFormsApi::VBA108678, data:) }

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

      it 'emits exactly the 55 fields defined in the data dictionary' do
        expect(described_class.convert(form).size).to eq(55)
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

    it 'derives APP_CALENDAR_YEAR from signatureDate when not explicit' do
      expect(described_class.convert(form)['APP_CALENDAR_YEAR']).to eq('2026')
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

    context 'when an explicit appCalendarYear is provided' do
      before { data['app_calendar_year'] = '2025' }

      it 'prefers the explicit value over the derived one' do
        expect(described_class.convert(form)['APP_CALENDAR_YEAR']).to eq('2025')
      end
    end
  end

  describe 'impactedLocations rendering' do
    let(:data) do
      {
        'appliances' => [
          { 'impacted_locations' => locations }
        ]
      }
    end

    context 'with a single quadrant set' do
      let(:locations) do
        { 'upper_left' => true,
          'upper_right' => false,
          'lower_left' => false,
          'lower_right' => false }
      end

      it 'emits the matching label' do
        expect(described_class.convert(form)['IMPACTED_LOC_APPLIANCE_1']).to eq('Upper Left')
      end
    end

    context 'with multiple quadrants set' do
      let(:locations) { { 'upper_left' => true, 'upper_right' => true, 'lower_left' => false, 'lower_right' => true } }

      it 'joins labels in the canonical order' do
        expect(described_class.convert(form)['IMPACTED_LOC_APPLIANCE_1']).to eq('Upper Left, Upper Right, Lower Right')
      end
    end

    context 'with no quadrants set' do
      let(:locations) do
        { 'upper_left' => false,
          'upper_right' => false,
          'lower_left' => false,
          'lower_right' => false }
      end

      it 'returns an empty string' do
        expect(described_class.convert(form)['IMPACTED_LOC_APPLIANCE_1']).to eq('')
      end
    end

    context 'when impactedLocations is missing' do
      let(:data) { { 'appliances' => [{}] } }

      it 'returns an empty string' do
        expect(described_class.convert(form)['IMPACTED_LOC_APPLIANCE_1']).to eq('')
      end
    end
  end

  describe 'helper behavior' do
    let(:data) { {} }

    describe '.normalize_ssn' do
      it 'strips dashes and non-digits' do
        expect(described_class.normalize_ssn('123-45-6789')).to eq('123456789')
      end

      it 'returns empty string for nil' do
        expect(described_class.normalize_ssn(nil)).to eq('')
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

    describe '.issue_date' do
      it 'formats ISO dates as MM/YYYY' do
        expect(described_class.issue_date('2024-06-01')).to eq('06/2024')
      end

      it 'handles {month, year} hashes' do
        expect(described_class.issue_date('month' => '6', 'year' => '2024')).to eq('06/2024')
      end

      it 'returns empty for nil' do
        expect(described_class.issue_date(nil)).to eq('')
      end
    end

    describe '.approved_state' do
      it 'returns :unset when value is nil or blank' do
        expect(described_class.approved_state(nil)).to eq(:unset)
        expect(described_class.approved_state('')).to eq(:unset)
      end

      it 'recognizes booleans' do
        expect(described_class.approved_state(true)).to eq(:yes)
        expect(described_class.approved_state(false)).to eq(:no)
      end
    end
  end

  describe 'edge cases' do
    context 'when the appliances array has more than 5 entries' do
      let(:data) do
        {
          'appliances' => Array.new(7) { |i| { 'device_or_medication' => "Appliance #{i + 1}" } }
        }
      end

      it 'truncates to 5' do
        result = described_class.convert(form)
        expect(result['NAME_APPLIANCE_5']).to eq('Appliance 5')
        expect(result.keys).not_to include('NAME_APPLIANCE_6')
      end
    end

    context 'when appliances is missing entirely' do
      let(:data) { {} }

      it 'still emits all five appliance slots as empty' do
        result = described_class.convert(form)
        (1..5).each do |i|
          expect(result["NAME_APPLIANCE_#{i}"]).to eq('')
          expect(result["VA_APPROVED_YES_APPLIANCE_#{i}"]).to eq(0)
          expect(result["VA_APPROVED_NO_APPLIANCE_#{i}"]).to eq(0)
        end
      end
    end

    context 'when the data dictionary requires fields the form does not collect' do
      let(:data) { JSON.parse(File.read(fixture_dir.join('vba_10_8678.json'))) }

      it 'leaves For-VA-Use-Only fields as empty strings' do
        result = described_class.convert(form)
        %w[ELIGIBLE NOT_ELIGIBLE UPPER_EXTREMITY LOWER_EXTREMITY
           GENERATED_BY DATE_GENERATED_BY AUTHORIZED_BY DATE_AUTHORIZED_BY EXAM_DATE].each do |field|
          expect(result[field]).to eq('')
        end
      end
    end
  end
end
