# frozen_string_literal: true

require 'rails_helper'
require SimpleFormsApi::Engine.root.join(
  'app', 'services', 'simple_forms_api', 'mms', 'vba_21_0788_ibm_converter'
)

RSpec.describe SimpleFormsApi::Mms::VBA210788IbmConverter do
  let(:fixture_dir) { SimpleFormsApi::Engine.root.join('spec', 'fixtures', 'form_json') }

  let(:form) { instance_double(SimpleFormsApi::VBA210788, data:) }

  describe '.convert' do
    context 'with the 21-0788 fixture' do
      let(:data) { JSON.parse(File.read(fixture_dir.join('vba_21_0788.json'))) }
      let(:expected) { JSON.parse(File.read(fixture_dir.join('vba_21_0788_ibm_payload.json'))) }

      it 'produces the expected MMS payload' do
        expect(described_class.convert(form)).to eq(expected)
      end

      it 'returns keys sorted alphabetically' do
        keys = described_class.convert(form).keys
        expect(keys).to eq(keys.sort)
      end

      it 'emits exactly the 62 fields defined in the data dictionary' do
        expect(described_class.convert(form).size).to eq(62)
      end

      it 'preserves the data dictionary field names verbatim, typos included' do
        result = described_class.convert(form)
        expect(result).to have_key('APPORTION_CURRENTLY_IN RECEPIENT_YES_1')
        expect(result).to have_key('APPORTION_CURRENTLY_IN RECEPIENT_NO_4')
        expect(result).to have_key('PRIMARY _BENEFICIARY_RESIDES_OUTSUDE_US')
      end
    end
  end

  describe 'field-level transformations' do
    let(:data) do
      {
        'full_name' => { 'first' => 'John', 'middle' => 'David', 'last' => 'Doe' },
        'ssn' => '123-45-6789',
        'va_file_number' => 'C12-345-678',
        'date_of_birth' => '1980-02-03',
        'claimant_full_name' => { 'first' => 'Mary', 'middle' => 'Anne', 'last' => 'Doe' },
        'relationship' => 'spouse',
        'address' => {
          'street' => '123 Main St',
          'street2' => 'Apt 4B',
          'city' => 'Springfield',
          'state' => 'PA',
          'postal_code' => '22150',
          'country' => 'USA'
        },
        'phone' => '(703) 555-1234',
        'email_address' => 'mary.doe@example.com',
        'claimant_signature' => 'Mary Anne Doe',
        'signature_date' => '2026-04-16',
        'apportionment_recipients' => []
      }
    end

    it 'formats the veteran name as LAST, FIRST, MIDDLE' do
      expect(described_class.convert(form)['VETERAN_NAME']).to eq('Doe, John, David')
    end

    it 'splits the veteran name into first, middle initial, and last' do
      result = described_class.convert(form)
      expect(result['VETERAN_FIRST_NAME']).to eq('John')
      expect(result['VETERAN_MIDDLE_INITIAL']).to eq('D')
      expect(result['VETERAN_LAST_NAME']).to eq('Doe')
    end

    it 'strips dashes from the SSN' do
      expect(described_class.convert(form)['VETERAN_SSN']).to eq('123456789')
    end

    it 'strips dashes from the VA file number but keeps an alpha prefix' do
      expect(described_class.convert(form)['VA_FILE_NUMBER']).to eq('C12345678')
    end

    it 'converts ISO dates to MM/DD/YYYY' do
      result = described_class.convert(form)
      expect(result['VETERAN_DOB']).to eq('02/03/1980')
      expect(result['CLAIMANT_SIGNATURE_DATE']).to eq('04/16/2026')
    end

    it 'flattens the claimant address block with city/state ZIP and country' do
      expect(described_class.convert(form)['CLAIMANT_ADDRESS_FULL_BLOCK']).to eq(
        "123 Main St Apt 4B\nSpringfield, PA 22150\nUSA"
      )
    end

    it 'strips formatting from the telephone number' do
      expect(described_class.convert(form)['CLAIMANT_TELEPHONE_NUMBER']).to eq('7035551234')
    end

    it 'sets CLAIMANT_SIGNATURE to 1 when a signature is present' do
      expect(described_class.convert(form)['CLAIMANT_SIGNATURE']).to eq(1)
    end

    context 'when the signature is blank' do
      before { data['claimant_signature'] = '' }

      it 'sets CLAIMANT_SIGNATURE to 0' do
        expect(described_class.convert(form)['CLAIMANT_SIGNATURE']).to eq(0)
      end
    end

    it 'stamps the form type label on both pages' do
      result = described_class.convert(form)
      expect(result['FORM_TYPE']).to eq('VA FORM 21-0788 FEB 2026')
      expect(result['FORM_TYPE_1']).to eq('VA FORM 21-0788 FEB 2026')
    end
  end

  describe 'relationship checkboxes' do
    let(:data) { { 'relationship' => relationship } }

    {
      'spouse' => 'CURRENT_SPOUSE',
      'child_18_23' => 'CHILD_18_23_IN_SCHOOL',
      'custodian' => 'CUSTODIAN',
      'parent' => 'DEPENDENT_PARENT',
      'child_disabled' => 'CHILD_OVER_18'
    }.each do |value, field|
      context "when relationship is #{value}" do
        let(:relationship) { value }

        it "checks only #{field}" do
          result = described_class.convert(form)
          expect(result[field]).to eq(1)
          checked = described_class::RELATIONSHIP_CHECKBOXES.keys.select { |k| result[k] == 1 }
          expect(checked).to eq([field])
          expect(result['OTHER']).to eq('')
        end
      end
    end

    context 'when relationship is other' do
      let(:data) { { 'relationship' => 'other', 'other_relationship' => 'Former spouse' } }

      it 'leaves all checkboxes unchecked and carries the free text in OTHER' do
        result = described_class.convert(form)
        described_class::RELATIONSHIP_CHECKBOXES.each_key do |field|
          expect(result[field]).to eq(0)
        end
        expect(result['OTHER']).to eq('Former spouse')
      end
    end
  end

  describe 'stepchild yes/no pairs' do
    let(:data) do
      {
        'stepchild_living_in_household' => in_household,
        'legally_adopted' => adopted
      }
    end

    context 'when answered yes/no' do
      let(:in_household) { true }
      let(:adopted) { false }

      it 'checks exactly one box per pair' do
        result = described_class.convert(form)
        expect(result['VETERAN_STEP_CHILD_YES']).to eq(1)
        expect(result['VETERAN_STEP_CHILD_NO']).to eq(0)
        expect(result['VETERAN_STEP_CHILD_ADOPTED_YES']).to eq(0)
        expect(result['VETERAN_STEP_CHILD_ADOPTED_NO']).to eq(1)
      end
    end

    context 'when unanswered' do
      let(:in_household) { nil }
      let(:adopted) { nil }

      it 'leaves both boxes of each pair unchecked' do
        result = described_class.convert(form)
        expect(result['VETERAN_STEP_CHILD_YES']).to eq(0)
        expect(result['VETERAN_STEP_CHILD_NO']).to eq(0)
        expect(result['VETERAN_STEP_CHILD_ADOPTED_YES']).to eq(0)
        expect(result['VETERAN_STEP_CHILD_ADOPTED_NO']).to eq(0)
      end
    end
  end

  describe 'apportionment reason checkboxes' do
    let(:data) { { 'apportionment_reason' => 'veteran_incarcerated_felony' } }

    it 'checks only the selected reason' do
      result = described_class.convert(form)
      expect(result['VETERAN_INCARCERATED_FELONY']).to eq(1)
      checked = described_class::REASON_CHECKBOXES.keys.select { |k| result[k] == 1 }
      expect(checked).to eq(['VETERAN_INCARCERATED_FELONY'])
    end

    context 'when no reason is given' do
      let(:data) { {} }

      it 'leaves all reason boxes unchecked' do
        result = described_class.convert(form)
        described_class::REASON_CHECKBOXES.each_key do |field|
          expect(result[field]).to eq(0)
        end
      end
    end
  end

  describe 'apportionee repeated section' do
    context 'with tri-state currently-in-receipt values' do
      let(:data) do
        {
          'apportionment_recipients' => [
            { 'currently_in_receipt' => true },
            { 'currently_in_receipt' => false },
            {}
          ]
        }
      end

      it 'checks YES, NO, or neither per entry' do
        result = described_class.convert(form)
        expect(result['APPORTION_CURRENTLY_IN RECEPIENT_YES_1']).to eq(1)
        expect(result['APPORTION_CURRENTLY_IN RECEPIENT_NO_1']).to eq(0)
        expect(result['APPORTION_CURRENTLY_IN RECEPIENT_YES_2']).to eq(0)
        expect(result['APPORTION_CURRENTLY_IN RECEPIENT_NO_2']).to eq(1)
        expect(result['APPORTION_CURRENTLY_IN RECEPIENT_YES_3']).to eq(0)
        expect(result['APPORTION_CURRENTLY_IN RECEPIENT_NO_3']).to eq(0)
      end
    end

    context 'when the recipients array has more than 4 entries' do
      let(:data) do
        {
          'apportionment_recipients' => Array.new(6) do |i|
            { 'full_name' => { 'first' => "Kid#{i + 1}", 'last' => 'Doe' } }
          end
        }
      end

      it 'truncates to 4' do
        result = described_class.convert(form)
        expect(result['NAME_APPORTIONMENT_REQUESTED_4']).to eq('Doe, Kid4')
        expect(result.keys).not_to include('NAME_APPORTIONMENT_REQUESTED_5')
      end
    end

    context 'when recipients are missing entirely' do
      let(:data) { {} }

      it 'still emits all four slots as empty' do
        result = described_class.convert(form)
        (1..4).each do |i|
          expect(result["NAME_APPORTIONMENT_REQUESTED_#{i}"]).to eq('')
          expect(result["APPORTION_SSN_#{i}"]).to eq('')
          expect(result["APPORTION_RELATIONSHIP_TO_VETERAN_#{i}"]).to eq('')
          expect(result["APPORTION_CURRENTLY_IN RECEPIENT_YES_#{i}"]).to eq(0)
          expect(result["APPORTION_CURRENTLY_IN RECEPIENT_NO_#{i}"]).to eq(0)
        end
      end
    end
  end

  describe 'helper behavior' do
    let(:data) { {} }

    describe '.format_iso_date' do
      it 'formats ISO 8601 dates as MM/DD/YYYY' do
        expect(described_class.format_iso_date('2026-04-16')).to eq('04/16/2026')
      end

      it 'handles {month, day, year} hashes' do
        expect(described_class.format_iso_date('month' => '4', 'day' => '16', 'year' => '2026'))
          .to eq('04/16/2026')
      end

      it 'returns empty string for nil or unparseable input' do
        expect(described_class.format_iso_date(nil)).to eq('')
        expect(described_class.format_iso_date('not a date')).to eq('')
      end
    end

    describe '.phone_digits' do
      it 'strips formatting from a string phone' do
        expect(described_class.phone_digits('(703) 555-1234')).to eq('7035551234')
      end

      it 'handles a hash with area_code and number' do
        expect(described_class.phone_digits('area_code' => '703', 'number' => '5551234'))
          .to eq('7035551234')
      end
    end

    describe '.tri_state' do
      it 'returns :unset for nil or blank' do
        expect(described_class.tri_state(nil)).to eq(:unset)
        expect(described_class.tri_state('')).to eq(:unset)
      end

      it 'recognizes booleans and string notations' do
        expect(described_class.tri_state(true)).to eq(:yes)
        expect(described_class.tri_state('Y')).to eq(:yes)
        expect(described_class.tri_state(false)).to eq(:no)
        expect(described_class.tri_state('0')).to eq(:no)
      end
    end

    describe '.middle_initial' do
      let(:data) { { 'full_name' => { 'first' => 'John', 'middle' => 'david', 'last' => 'Doe' } } }

      it 'upcases and truncates the middle name to one character' do
        expect(described_class.convert(form)['VETERAN_MIDDLE_INITIAL']).to eq('D')
      end
    end
  end

  describe 'edge cases' do
    context 'with completely empty data' do
      let(:data) { {} }

      it 'emits all 62 fields with no nils' do
        result = described_class.convert(form)
        expect(result.size).to eq(62)
        expect(result.values).not_to include(nil)
      end
    end
  end
end
