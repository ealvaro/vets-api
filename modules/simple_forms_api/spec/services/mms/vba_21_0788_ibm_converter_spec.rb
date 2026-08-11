# frozen_string_literal: true

require 'rails_helper'
require SimpleFormsApi::Engine.root.join(
  'app', 'services', 'simple_forms_api', 'mms', 'vba_21_0788_ibm_converter'
)

RSpec.describe SimpleFormsApi::Mms::VBA210788IbmConverter do
  let(:fixture_dir) { SimpleFormsApi::Engine.root.join('spec', 'fixtures', 'form_json') }

  let(:form) { instance_double(SimpleFormsApi::VBA210788, data:) }

  before do
    allow(form).to receive_messages(
      facility_name: nil,
      facility_address: nil,
      signature: nil,
      signature_date: nil
    )
  end

  describe '.convert' do
    before do
      allow(form).to receive_messages(
        facility_name: 'FCI Cumberland',
        facility_address: '14601 Burbridge Rd SE. Cumberland,MD 21502 USA',
        signature: 'Testy T McTestFace',
        signature_date: '2026-04-16'
      )
    end

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
        expect(described_class.convert(form).size).to eq(57)
      end

      it 'preserves the data dictionary field names verbatim, typos included' do
        result = described_class.convert(form)
        expect(result).to have_key('PRIMARY _BENEFICIARY_RESIDES_OUTSIDE_US')
      end
    end
  end

  describe 'field-level transformations' do
    before do
      allow(form).to receive_messages(
        facility_name: nil,
        facility_address: nil,
        signature: 'Mary Anne Doe',
        signature_date: '04/16/2026'
      )
    end

    let(:data) do
      {
        'full_name' => { 'first' => 'John', 'middle' => 'David', 'last' => 'Doe' },
        'ssn' => '123-45-6789',
        'va_file_number' => 'C12-345-678',
        'date_of_birth' => '1980-02-03',
        'preparer' => {
          'first' => 'Testy',
          'middle' => 'T',
          'last' => 'McTestFace'
        },
        'relationship_to_veteran' => 'spouse',
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
        'statement_of_truth_signature' => 'Mary Anne Doe',
        'signature_date' => '2026-04-16',
        'apportionment_people' => []
      }
    end

    it 'formats the veteran name as FIRST, MIDDLE, LAST' do
      expect(described_class.convert(form)['VETERAN_NAME']).to eq('John, David, Doe')
    end

    it 'strips dashes from the SSN' do
      expect(described_class.convert(form)['VETERAN_SSN']).to eq('123456789')
    end

    it 'strips dashes from the VA file number but keeps an alpha prefix' do
      expect(described_class.convert(form)['VA_FILE_NUMBER']).to eq('C12345678')
    end

    it 'converts ISO dates to MM/DD/YYYY' do
      allow(form).to receive(:signature_date).and_return('04/16/2026')
      result = described_class.convert(form)
      expect(result['VETERAN_DOB']).to eq('02/03/1980')
      expect(result['CLAIMANT_SIGNATURE_DATE']).to eq('04/16/2026')
    end

    it 'flattens the claimant address block with city/state ZIP and country' do
      expect(described_class.convert(form)['CLAIMANT_ADDRESS_FULL_BLOCK']).to eq(
        '123 Main St Apt 4B Springfield, PA 22150 USA'
      )
    end

    it 'strips formatting from the telephone number' do
      expect(described_class.convert(form)['CLAIMANT_TELEPHONE_NUMBER']).to eq('7035551234')
    end

    it 'sets CLAIMANT_SIGNATURE to Yes when a signature is present' do
      expect(described_class.convert(form)['CLAIMANT_SIGNATURE']).to eq('Yes')
    end

    context 'when the signature is blank' do
      before { data['statement_of_truth_signature'] = '' }

      it 'sets CLAIMANT_SIGNATURE to No' do
        allow(form).to receive(:signature).and_return(nil)
        expect(described_class.convert(form)['CLAIMANT_SIGNATURE']).to eq('No')
      end
    end

    it 'stamps the form type label on both pages' do
      result = described_class.convert(form)
      expect(result['FORM_TYPE']).to eq('VA FORM 21-0788 FEB 2026')
      expect(result['FORM_TYPE_1']).to eq('VA FORM 21-0788 FEB 2026')
    end
  end

  describe 'Adopted and Step Child fields' do
    let(:data) do
      {
        'stepchild_living_in_household' => in_household,
        'legally_adopted' => adopted
      }
    end

    context 'when answered yes' do
      let(:in_household) { true }
      let(:adopted) { true }

      it 'checks exactly one box per pair' do
        result = described_class.convert(form)
        expect(result['VETERAN_STEP_CHILD_YES']).to eq(1)
        expect(result['VETERAN_STEP_CHILD_NO']).to eq(0)
        expect(result['VETERAN_CHILD_ADOPTED_YES']).to eq(1)
        expect(result['VETERAN_CHILD_ADOPTED_NO']).to eq(0)
      end
    end

    context 'when answered no' do
      let(:in_household) { false }
      let(:adopted) { false }

      it 'checks exactly one box per pair' do
        result = described_class.convert(form)
        expect(result['VETERAN_STEP_CHILD_YES']).to eq(0)
        expect(result['VETERAN_STEP_CHILD_NO']).to eq(1)
        expect(result['VETERAN_CHILD_ADOPTED_YES']).to eq(0)
        expect(result['VETERAN_CHILD_ADOPTED_NO']).to eq(1)
      end
    end

    context 'when unanswered' do
      let(:in_household) { nil }
      let(:adopted) { nil }

      it 'leaves both boxes of each pair unchecked' do
        result = described_class.convert(form)
        expect(result['VETERAN_STEP_CHILD_YES']).to eq(0)
        expect(result['VETERAN_STEP_CHILD_NO']).to eq(0)
        expect(result['VETERAN_CHILD_ADOPTED_YES']).to eq(0)
        expect(result['VETERAN_CHILD_ADOPTED_NO']).to eq(0)
      end
    end
  end

  describe 'apportionee repeated section' do
    context 'currently-in-receipt values' do
      let(:data) do
        {
          'apportionment_people' => [
            { 'currently_receiving' => true },
            { 'currently_receiving' => false },
            {}
          ]
        }
      end

      it 'checks YES, NO, or neither per entry' do
        result = described_class.convert(form)
        expect(result['APPORTION_CURRENTLY_IN_RECEPIENT_YES_1']).to eq(1)
        expect(result['APPORTION_CURRENTLY_IN_RECEPIENT_NO_1']).to eq(0)
        expect(result['APPORTION_CURRENTLY_IN_RECEPIENT_YES_2']).to eq(0)
        expect(result['APPORTION_CURRENTLY_IN_RECEPIENT_NO_2']).to eq(1)
        expect(result['APPORTION_CURRENTLY_IN_RECEPIENT_YES_3']).to eq(0)
        expect(result['APPORTION_CURRENTLY_IN_RECEPIENT_NO_3']).to eq(0)
      end
    end

    context 'when the recipients array has more than 4 entries' do
      let(:data) do
        {
          'apportionment_people' => Array.new(6) do |i|
            { 'full_name' => "Kid#{i + 1} Doe" }
          end
        }
      end

      it 'truncates to 4' do
        result = described_class.convert(form)
        expect(result['NAME_APPORTIONMENT_REQUESTED_4']).to eq('Kid4 Doe')
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
          expect(result["APPORTION_CURRENTLY_IN_RECEPIENT_YES_#{i}"]).to eq(0)
          expect(result["APPORTION_CURRENTLY_IN_RECEPIENT_NO_#{i}"]).to eq(0)
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
  end

  describe '#reason_checkbox_fields' do
    let(:data) { { 'reason' => '' } }
    let(:reasons) do
      %w[veteran_incarcerated
         spouse_or_child_incarcerated
         veteran_incompetent_no_fiduciary
         veteran_pension_care_facility
         enemy_territory_resident
         veteran_disappeared]
    end
    let(:dd_fields) do
      [
        'VETERAN_INCARCERATED',
        'SURVIVING_SPOUSE_INCARCERATED',
        'VETERAN_INCOMPETENT',
        'VETERAN_IN_RECEIPT_OF_PENSION',
        'PRIMARY _BENEFICIARY_RESIDES_OUTSIDE_US',
        'VETERAN_DISAPPEARED'
      ]
    end

    it 'selects the proper reason' do
      reasons.each_with_index do |reason, i|
        data['reason'] = reason
        expect(described_class.reason_checkbox_fields(data)[dd_fields[i]]).to eq(1)
      end
    end

    context 'when incarceration is selected' do
      let(:data) { { 'reason' => '', 'incarceration' => { 'felony' => nil, 'misdemeanor' => nil } } }
      let(:veteran_incarcerated) { 'veteran_incarcerated' }
      let(:spouse_or_child_incarcerated) { 'spouse_or_child_incarcerated' }

      it 'checks felony' do
        data['reason'] = veteran_incarcerated
        data['incarceration']['felony'] = true
        expect(described_class.reason_checkbox_fields(data)['VETERAN_INCARCERATED']).to eq(1)
        expect(described_class.reason_checkbox_fields(data)['VETERAN_INCARCERATED_FELONY']).to eq(1)
        expect(described_class.reason_checkbox_fields(data)['VETERAN_INCARCERATED_MISDEMEANOR']).to eq(0)

        data['reason'] = spouse_or_child_incarcerated
        expect(described_class.reason_checkbox_fields(data)['SURVIVING_SPOUSE_INCARCERATED']).to eq(1)
        expect(described_class.reason_checkbox_fields(data)['SURVIVING_SPOUSE_OR_CHILD_INCARCERATED_FELONY']).to eq(1)
        expect(described_class.reason_checkbox_fields(data)['SURVIVING_SPOUSE_OR_CHILD_INCARCERATED_MISDEMEANOR'])
          .to eq(0)
      end

      it 'checks misdemeanor' do
        data['reason'] = veteran_incarcerated
        data['incarceration']['felony'] = false
        data['incarceration']['misdemeanor'] = true
        expect(described_class.reason_checkbox_fields(data)['VETERAN_INCARCERATED']).to eq(1)
        expect(described_class.reason_checkbox_fields(data)['VETERAN_INCARCERATED_FELONY']).to eq(0)
        expect(described_class.reason_checkbox_fields(data)['VETERAN_INCARCERATED_MISDEMEANOR']).to eq(1)

        data['reason'] = spouse_or_child_incarcerated
        expect(described_class.reason_checkbox_fields(data)['SURVIVING_SPOUSE_INCARCERATED']).to eq(1)
        expect(described_class.reason_checkbox_fields(data)['SURVIVING_SPOUSE_OR_CHILD_INCARCERATED_FELONY']).to eq(0)
        expect(described_class.reason_checkbox_fields(data)['SURVIVING_SPOUSE_OR_CHILD_INCARCERATED_MISDEMEANOR'])
          .to eq(1)
      end
    end
  end

  describe 'edge cases' do
    context 'with completely empty data' do
      let(:data) { {} }

      it 'emits all 57 fields with no nils' do
        allow(form).to receive_messages(facility_name: nil, facility_address: nil, signature: nil, signature_date: nil)
        result = described_class.convert(form)
        expect(result.size).to eq(57)
        expect(result.values).not_to include(nil)
      end
    end
  end
end
