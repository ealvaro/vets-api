# frozen_string_literal: true

# spec/services/mss/form4502_ibm_converter_spec.rb

require 'rails_helper'
require SimpleFormsApi::Engine.root.join('spec', 'spec_helper.rb')

RSpec.describe SimpleFormsApi::Mms::VBA214502IbmConverter do
  let(:fixture_file) { 'vba_21_4502.json' }
  let(:min_file) { 'vba_21_4502-min.json' }
  let(:fixture_path) do
    Rails.root.join('modules', 'simple_forms_api', 'spec', 'fixtures', 'form_json', fixture_file)
  end
  let(:min_example_path) do
    Rails.root.join('modules', 'simple_forms_api', 'spec', 'fixtures', 'form_json', min_file)
  end
  let(:data) { JSON.parse(File.read(fixture_path)) }
  let(:form) { SimpleFormsApi::VBA214502.new(data) }

  let(:ibm_fixture_file) { 'vba_21_4502_ibm_payload.json' }
  let(:ibm_fixture_path) do
    Rails.root.join('modules', 'simple_forms_api', 'spec', 'fixtures', 'form_json', ibm_fixture_file)
  end
  let(:ibm_payload) { JSON.parse(File.read(ibm_fixture_path)) }

  describe '#convert' do
    subject(:payload) { described_class.convert(form) }

    it 'converts a parsed form to the keys and formats expected by IBM' do
      expect(payload).to eq(ibm_payload)
    end

    it 'uses blank string for missing data' do
      min_form = JSON.parse(File.read(min_example_path))
      form = SimpleFormsApi::VBA214502.new(min_form)
      ibm_payload = described_class.convert(form)

      expect(ibm_payload['VA_FILE_NUMBER']).to eq('')
      expect(ibm_payload['VETERAN_DOB']).to eq('')
      expect(ibm_payload['VETERAN_SSN']).to eq('')
      expect(ibm_payload['VETERAN_SSN_1']).to eq('')
      expect(ibm_payload['VETERAN_SERVICE_NUMBER']).to eq('')
      expect(ibm_payload['INT_PHONE_NUMBER']).to eq('')
      expect(ibm_payload['CURRENT_ADDRESS_LINE2']).to eq('')
      expect(ibm_payload['DATE_ENTERED_TO_SERVICE']).to eq('')
      expect(ibm_payload['DATE_SEPARATED_FROM_SERVICE']).to eq('')
      expect(ibm_payload['DATE_APPLIED_DISABILITY']).to eq('')
      expect(ibm_payload['APPLIED_DISABILITY_PLACE']).to eq('')
      expect(ibm_payload['VA_LOCATION_WITH_FILE']).to eq('')
      expect(ibm_payload['DATE_PREVIOUS_APPLIED']).to eq('')
      expect(ibm_payload['PLACE_PREVIOUS_APPLIED']).to eq('')
      expect(ibm_payload['TYPE_CONVEYANCE_OTHER_SPECIFY']).to eq('')
    end

    it 'normalizes SSN' do
      expect(payload['VETERAN_SSN']).to eq('123456789')
    end

    it 'repeats SSN at top of page 2' do
      expect(payload['VETERAN_SSN_1']).to eq(payload['VETERAN_SSN'])
    end

    it 'formats DOB as MM/DD/YYYY' do
      expect(payload['VETERAN_DOB']).to eq('01/01/1980')
    end

    it 'preserves email casing' do
      # NOTE: 21-4140 downcases email, but 21-4502 reads form.data['email'] directly.
      expect(payload['EMAIL']).to eq('taylor.veteran@example.com')
    end

    it 'includes full name fields correctly' do
      expect(payload['VETERAN_FIRST_NAME']).to eq('Taylor')
      expect(payload['VETERAN_MIDDLE_INITIAL']).to eq('A')
      expect(payload['VETERAN_LAST_NAME']).to eq('Veteran')
    end

    it 'truncates middle initial to a single character' do
      data_with_long_middle = data.deep_dup
      data_with_long_middle['full_name']['middle'] = 'Theodore'
      form_with_long_middle = SimpleFormsApi::VBA214502.new(data_with_long_middle)

      result = described_class.convert(form_with_long_middle)
      expect(result['VETERAN_MIDDLE_INITIAL']).to eq('T')
    end

    it 'normalizes phone number to digits only' do
      expect(payload['PHONE_NUMBER']).to match(/\A\d{10}\z/)
    end

    it 'concatenates international phone parts to digits only' do
      expect(payload['INT_PHONE_NUMBER']).to match(/\A\d+\z/)
    end

    it 'normalizes ZIP to first 5 digits' do
      expect(payload['CURRENT_ADDRESS_ZIP5']).to match(/\A\d{5}\z/)
    end

    describe 'electronic correspondence checkbox' do
      it 'returns "1" when true' do
        data['electronic_correspondence'] = true
        expect(described_class.convert(SimpleFormsApi::VBA214502.new(data))['AGREE_ELECTRONIC_CORR']).to eq(1)
      end

      it 'returns "0" when false' do
        data['electronic_correspondence'] = false
        expect(described_class.convert(SimpleFormsApi::VBA214502.new(data))['AGREE_ELECTRONIC_CORR']).to eq(0)
      end

      it 'returns "0" when missing' do
        data.delete('electronic_correspondence')
        expect(described_class.convert(SimpleFormsApi::VBA214502.new(data))['AGREE_ELECTRONIC_CORR']).to eq(0)
      end
    end

    describe 'address selection' do
      it 'uses current_mailing_address when not on active duty' do
        data['active_duty'] = false
        data['current_mailing_address'] = {
          'street' => '123 Current St',
          'city' => 'Currentville',
          'state' => 'VA',
          'postal_code' => '22301',
          'country' => 'US'
        }
        result = described_class.convert(SimpleFormsApi::VBA214502.new(data))
        expect(result['CURRENT_ADDRESS_LINE1']).to eq('123 Current St')
        expect(result['CURRENT_ADDRESS_CITY']).to eq('Currentville')
      end

      it 'uses planned_mailing_address when active duty and planned address is provided' do
        data['active_duty'] = true
        data['planned_mailing_address'] = {
          'street' => '456 Planned Rd',
          'city' => 'Plannedburg',
          'state' => 'TX',
          'postal_code' => '75001',
          'country' => 'US'
        }
        result = described_class.convert(SimpleFormsApi::VBA214502.new(data))
        expect(result['PLANNED_ADDRESS_LINE1']).to eq('456 Planned Rd')
        expect(result['CURRENT_ADDRESS_LINE1']).to eq('123 Main St')
        expect(result['PLANNED_ADDRESS_CITY']).to eq('Plannedburg')
      end

      it 'falls back to current_mailing_address when active duty but planned is empty' do
        data['active_duty'] = true
        data['planned_mailing_address'] = {}
        data['current_mailing_address'] = {
          'street' => '123 Current St',
          'city' => 'Currentville'
        }
        result = described_class.convert(SimpleFormsApi::VBA214502.new(data))
        expect(result['CURRENT_ADDRESS_LINE1']).to eq('123 Current St')
      end
    end

    describe 'branch of service checkboxes' do
      {
        'ARMY' => 'BRANCH_OF_SERVICE_ARMY',
        'NAVY' => 'BRANCH_OF_SERVICE_NAVY',
        'AIR FORCE' => 'BRANCH_OF_SERVICE_AIR-FORCE',
        'MARINE CORPS' => 'BRANCH_OF_SERVICE_MARINE',
        'COAST GUARD' => 'BRANCH_OF_SERVICE_COAST-GUARD',
        'SPACE FORCE' => 'BRANCH_OF_SERVICE_SPACE',
        'NOAA' => 'BRANCH_OF_SERVICE_NOAA',
        'USPHS' => 'BRANCH_OF_SERVICE_USPHS'
      }.each do |branch_value, expected_field|
        it "checks only #{expected_field} when branch is #{branch_value}" do
          data['branch_of_service'] = branch_value
          result = described_class.convert(SimpleFormsApi::VBA214502.new(data))

          expect(result[expected_field]).to eq(1)

          other_branch_keys = result.keys.grep(/^BRANCH_OF_SERVICE_/) - [expected_field]
          other_branch_keys.each do |key|
            expect(result[key]).to eq(0), "expected #{key} to be 0 when branch is #{branch_value}"
          end
        end
      end

      it 'leaves all branch checkboxes unchecked when branch is unknown' do
        data['branch_of_service'] = 'FOREIGN LEGION'
        result = described_class.convert(SimpleFormsApi::VBA214502.new(data))
        result.keys.grep(/^BRANCH_OF_SERVICE_/).each do |key|
          expect(result[key]).to eq(0)
        end
      end
    end

    describe 'active duty radio (yes/no)' do
      it 'checks YES and unchecks NO when true' do
        data['active_duty'] = true
        result = described_class.convert(SimpleFormsApi::VBA214502.new(data))
        expect(result['ACTIVE_DUTY_YES']).to eq(1)
        expect(result['ACTIVE_DUTY_NO']).to eq(0)
      end

      it 'checks NO and unchecks YES when false' do
        data['active_duty'] = false
        result = described_class.convert(SimpleFormsApi::VBA214502.new(data))
        expect(result['ACTIVE_DUTY_YES']).to eq(0)
        expect(result['ACTIVE_DUTY_NO']).to eq(1)
      end

      it 'leaves both unchecked when missing' do
        data.delete('active_duty')
        result = described_class.convert(SimpleFormsApi::VBA214502.new(data))
        expect(result['ACTIVE_DUTY_YES']).to eq(0)
        expect(result['ACTIVE_DUTY_NO']).to eq(0)
      end
    end

    describe 'vehicle type / conveyance' do
      {
        'AUTOMOBILE' => 'AUTO',
        'STATION WAGON' => 'STAT_WAGON',
        'VAN' => 'VAN',
        'TRUCK' => 'TRUCK'
      }.each do |vehicle, suffix|
        it "checks only TYPE_CONVEYANCE_#{suffix} when vehicle_type is #{vehicle}" do
          data['vehicle_type'] = vehicle
          result = described_class.convert(SimpleFormsApi::VBA214502.new(data))

          expect(result["TYPE_CONVEYANCE_#{suffix}"]).to eq(1)
          expect(result['TYPE_CONVEYANCE_OTHER']).to eq(0)
          expect(result['TYPE_CONVEYANCE_OTHER_SPECIFY']).to eq('')
        end
      end

      it 'checks OTHER and populates OTHER_SPECIFY for unrecognized vehicle types' do
        data['vehicle_type'] = 'Motorcycle Sidecar'
        result = described_class.convert(SimpleFormsApi::VBA214502.new(data))

        expect(result['TYPE_CONVEYANCE_AUTO']).to eq(0)
        expect(result['TYPE_CONVEYANCE_STAT_WAGON']).to eq(0)
        expect(result['TYPE_CONVEYANCE_VAN']).to eq(0)
        expect(result['TYPE_CONVEYANCE_TRUCK']).to eq(0)
        expect(result['TYPE_CONVEYANCE_OTHER']).to eq(1)
        expect(result['TYPE_CONVEYANCE_OTHER_SPECIFY']).to eq('Motorcycle Sidecar')
      end
    end

    describe 'date formatting' do
      it 'formats structured date parts as MM/DD/YYYY' do
        data['signature_date'] = { 'month' => '04', 'day' => '15', 'year' => '2026' }
        result = described_class.convert(SimpleFormsApi::VBA214502.new(data))
        expect(result['DATE_OF_VETERAN_SIGNATURE']).to eq('04/15/2026')
      end

      it 'returns blank when date parts are missing' do
        data['signature_date'] = nil
        result = described_class.convert(SimpleFormsApi::VBA214502.new(data))
        expect(result['DATE_OF_VETERAN_SIGNATURE']).to eq('')
      end

      it 'returns blank when date parts are partial' do
        data['signature_date'] = { 'month' => '04', 'day' => '', 'year' => '2026' }
        result = described_class.convert(SimpleFormsApi::VBA214502.new(data))
        expect(result['DATE_OF_VETERAN_SIGNATURE']).to eq('')
      end
    end

    it 'returns a sorted hash' do
      expect(payload.keys).to eq(payload.keys.sort)
    end
  end
end
