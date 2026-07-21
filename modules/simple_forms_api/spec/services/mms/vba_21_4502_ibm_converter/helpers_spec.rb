# frozen_string_literal: true

require 'rails_helper'
require SimpleFormsApi::Engine.root.join(
  'app', 'services', 'simple_forms_api', 'mms', 'vba_21_4502_ibm_converter'
)

RSpec.describe SimpleFormsApi::Mms::VBA214502IbmConverter::Helpers do
  # Anonymous harness that mixes in the helpers, so we can call instance methods
  # without depending on the parent converter module under test.
  let(:harness) { Class.new { extend SimpleFormsApi::Mms::VBA214502IbmConverter::Helpers } }

  # Default form double — individual `describe` blocks override `data` and stub
  # `date_part` as needed.
  let(:data) { {} }
  let(:form) do
    instance_double(SimpleFormsApi::VBA214502, data:).tap do |dbl|
      allow(dbl).to receive(:date_part) do |key, part|
        value = data[key]
        value.is_a?(Hash) ? value[part.to_s] : nil
      end
    end
  end

  describe '#planned_address' do
    let(:planned) { { 'street' => '2 Elm', 'city' => 'Othertown', 'state' => 'PA', 'postal_code' => '15201' } }

    context 'when active_duty is true and planned_mailing_address has values' do
      let(:data) do
        {
          'active_duty' => true,
          'planned_mailing_address' => planned
        }
      end

      it 'returns the planned address' do
        expect(harness.planned_address(form)).to eq(planned)
      end
    end

    context 'when active_duty is false, planned_mailing_address return a empty hash' do
      let(:data) do
        {
          'active_duty' => false,
          'planned_mailing_address' => planned
        }
      end

      it 'returns the blank planned address' do
        expect(harness.planned_address(form)).to eq({})
      end
    end
  end

  describe '#current_address' do
    let(:current) { { 'street' => '1 Main', 'city' => 'Anytown', 'state' => 'VA', 'postal_code' => '22301' } }

    context 'current_mailing_address has values' do
      let(:data) do
        {
          'current_mailing_address' => current
        }
      end

      it 'returns the current address' do
        expect(harness.current_address(form)).to eq(current)
      end
    end

    context 'current_mailing_address has no values' do
      let(:data) do
        {
          'current_mailing_address' => {}
        }
      end

      it 'returns a empty hash' do
        expect(harness.current_address(form)).to eq({})
      end
    end
  end

  describe '#normalize_ssn' do
    it 'strips dashes and non-digits' do
      expect(harness.normalize_ssn('123-45-6789')).to eq('123456789')
    end

    it 'strips spaces and letters' do
      expect(harness.normalize_ssn('123 45 6789x')).to eq('123456789')
    end

    it 'returns an empty string for nil' do
      expect(harness.normalize_ssn(nil)).to eq('')
    end

    it 'returns an empty string when input has no digits' do
      expect(harness.normalize_ssn('---')).to eq('')
    end

    it 'coerces non-string input' do
      expect(harness.normalize_ssn(123_456_789)).to eq('123456789')
    end
  end

  describe '#domestic_phone' do
    context 'when phone_number is a full hash' do
      let(:data) { { 'phone_number' => { 'area_code' => '703', 'number' => '555-1234' } } }

      it 'concatenates and strips non-digits' do
        expect(harness.domestic_phone(form)).to eq('7035551234')
      end
    end

    context 'when phone_number is missing' do
      let(:data) { {} }

      it 'returns an empty string' do
        expect(harness.domestic_phone(form)).to eq('')
      end
    end

    context 'when phone_number has only an area code' do
      let(:data) { { 'phone_number' => { 'area_code' => '703' } } }

      it 'returns just the area code digits' do
        expect(harness.domestic_phone(form)).to eq('703')
      end
    end
  end

  describe '#international_phone' do
    context 'with a full hash' do
      let(:data) do
        { 'international_phone_number' => { 'country_code' => '+44', 'area_code' => '20', 'number' => '7946 0958' } }
      end

      it 'concatenates and strips non-digits' do
        expect(harness.international_phone(form)).to eq('442079460958')
      end
    end

    context 'when the value is nil' do
      let(:data) { {} }

      it 'returns an empty string' do
        expect(harness.international_phone(form)).to eq('')
      end
    end

    context 'when the value is not a hash' do
      let(:data) { { 'international_phone_number' => '+44 20 7946 0958' } }

      it 'returns an empty string (only hash input is supported)' do
        expect(harness.international_phone(form)).to eq('')
      end
    end

    context 'when some sub-parts are missing' do
      let(:data) { { 'international_phone_number' => { 'country_code' => '+44', 'number' => '7946 0958' } } }

      it 'still concatenates available parts' do
        expect(harness.international_phone(form)).to eq('4479460958')
      end
    end
  end

  describe '#normalize_zip' do
    it 'returns the first 5 digits of a ZIP+4' do
      expect(harness.normalize_zip('22301-1234')).to eq('22301')
    end

    it 'returns a 5-digit ZIP unchanged' do
      expect(harness.normalize_zip('22301')).to eq('22301')
    end

    it 'returns fewer digits if input has fewer' do
      expect(harness.normalize_zip('223')).to eq('223')
    end

    it 'strips spaces and letters' do
      expect(harness.normalize_zip(' 22301 abc')).to eq('22301')
    end

    it 'returns an empty string for nil' do
      expect(harness.normalize_zip(nil)).to eq('')
    end

    it 'returns an empty string when input has no digits' do
      expect(harness.normalize_zip('abc')).to eq('')
    end
  end

  describe '#bool_to_checkbox' do
    it 'returns "1" for true' do
      expect(harness.bool_to_checkbox(true)).to eq(1)
    end

    it 'returns "0" for false' do
      expect(harness.bool_to_checkbox(false)).to eq(0)
    end

    it 'returns "0" for nil' do
      expect(harness.bool_to_checkbox(nil)).to eq(0)
    end

    it 'recognizes truthy strings' do
      %w[1 true yes y t TRUE Yes].each do |v|
        expect(harness.bool_to_checkbox(v)).to eq(1)
      end
    end

    it 'returns "0" for other strings' do
      expect(harness.bool_to_checkbox('no')).to eq(0)
      expect(harness.bool_to_checkbox('false')).to eq(0)
    end
  end

  describe '#yes_checkbox' do
    it 'returns "1" for truthy values' do
      expect(harness.yes_checkbox(true)).to eq(1)
      expect(harness.yes_checkbox('yes')).to eq(1)
    end

    it 'returns "0" for falsy values' do
      expect(harness.yes_checkbox(false)).to eq(0)
      expect(harness.yes_checkbox(nil)).to eq(0)
    end
  end

  describe '#no_checkbox' do
    it 'returns "0" when value is truthy (i.e. user said yes)' do
      expect(harness.no_checkbox(true)).to eq(0)
      expect(harness.no_checkbox('yes')).to eq(0)
    end

    it 'returns "1" when value is explicitly false (user said no)' do
      expect(harness.no_checkbox(false)).to eq(1)
    end

    it 'returns "0" when value is nil (unanswered, neither box checked)' do
      expect(harness.no_checkbox(nil)).to eq(0)
    end
  end

  describe '#truthy?' do
    it 'returns false for nil' do
      expect(harness.truthy?(nil)).to be false
    end

    it 'returns the boolean itself for true/false' do
      expect(harness.truthy?(true)).to be true
      expect(harness.truthy?(false)).to be false
    end

    it 'returns true for recognized truthy strings' do
      %w[1 true yes y t].each do |v|
        expect(harness.truthy?(v)).to be true
      end
    end

    it 'is case-insensitive' do
      expect(harness.truthy?('TRUE')).to be true
      expect(harness.truthy?('Yes')).to be true
    end

    it 'returns false for everything else' do
      %w[0 false no n f maybe].each do |v|
        expect(harness.truthy?(v)).to be false
      end
    end
  end

  describe '#branch_checkbox' do
    context 'with a recognized branch' do
      let(:data) { { 'branch_of_service' => 'air force' } }

      it 'returns "1" when target_suffix matches the mapped value' do
        expect(harness.branch_checkbox(form, 'AIR-FORCE')).to eq(1)
      end

      it 'returns "0" for non-matching target suffixes' do
        expect(harness.branch_checkbox(form, 'ARMY')).to eq(0)
      end

      it 'uppercases the branch value before lookup' do
        data['branch_of_service'] = 'Marine Corps'
        expect(harness.branch_checkbox(form, 'MARINE')).to eq(1)
      end
    end

    context 'with an unrecognized branch' do
      let(:data) { { 'branch_of_service' => 'Foreign Legion' } }

      it 'returns "0" for every target suffix' do
        expect(harness.branch_checkbox(form, 'ARMY')).to eq(0)
        expect(harness.branch_checkbox(form, 'NAVY')).to eq(0)
      end
    end

    context 'when branch_of_service is missing' do
      let(:data) { {} }

      it 'returns "0"' do
        expect(harness.branch_checkbox(form, 'ARMY')).to eq(0)
      end
    end
  end

  describe '#conveyance_checkbox' do
    context 'with a recognized vehicle type' do
      let(:data) { { 'vehicle_type' => 'station wagon' } }

      it 'returns "1" when target_suffix matches' do
        expect(harness.conveyance_checkbox(form, 'STAT_WAGON')).to eq(1)
      end

      it 'returns "0" for non-matching suffixes' do
        expect(harness.conveyance_checkbox(form, 'AUTO')).to eq(0)
      end
    end

    context 'with an unrecognized vehicle type' do
      let(:data) { { 'vehicle_type' => 'Hovercraft' } }

      it 'returns "0" for any suffix in the map' do
        expect(harness.conveyance_checkbox(form, 'AUTO')).to eq(0)
      end
    end

    context 'when vehicle_type is missing' do
      let(:data) { {} }

      it 'returns "0"' do
        expect(harness.conveyance_checkbox(form, 'AUTO')).to eq(0)
      end
    end
  end

  describe '#conveyance_other_checkbox' do
    it 'returns "1" when vehicle_type is set but not in the map' do
      data['vehicle_type'] = 'Hovercraft'
      expect(harness.conveyance_other_checkbox(form)).to eq(1)
    end

    it 'returns "0" when vehicle_type matches a mapped value' do
      data['vehicle_type'] = 'AUTOMOBILE'
      expect(harness.conveyance_other_checkbox(form)).to eq(0)
    end

    it 'returns "0" when vehicle_type is empty' do
      data['vehicle_type'] = ''
      expect(harness.conveyance_other_checkbox(form)).to eq(0)
    end

    it 'returns "0" when vehicle_type is missing' do
      expect(harness.conveyance_other_checkbox(form)).to eq(0)
    end

    it 'is case-insensitive when checking the map' do
      data['vehicle_type'] = 'automobile'
      expect(harness.conveyance_other_checkbox(form)).to eq(0)
    end
  end

  describe '#conveyance_other_value' do
    it 'returns the raw vehicle_type when not in the map' do
      data['vehicle_type'] = 'Hovercraft'
      expect(harness.conveyance_other_value(form)).to eq('Hovercraft')
    end

    it 'preserves the original casing of the user-entered value' do
      data['vehicle_type'] = 'amphibious assault vehicle'
      expect(harness.conveyance_other_value(form)).to eq('amphibious assault vehicle')
    end

    it 'returns "" when vehicle_type matches a mapped value (case-insensitive)' do
      data['vehicle_type'] = 'automobile'
      expect(harness.conveyance_other_value(form)).to eq('')
    end

    it 'returns "" when vehicle_type is empty' do
      data['vehicle_type'] = ''
      expect(harness.conveyance_other_value(form)).to eq('')
    end

    it 'returns "" when vehicle_type is missing' do
      expect(harness.conveyance_other_value(form)).to eq('')
    end
  end

  describe '#date_parts_to_string' do
    context 'with a complete date hash' do
      let(:data) { { 'signature_date' => { 'month' => '4', 'day' => '7', 'year' => '2026' } } }

      it 'formats as MM/DD/YYYY with zero padding' do
        expect(harness.date_parts_to_string(form, 'signature_date')).to eq('04/07/2026')
      end

      it 'preserves already-padded values' do
        data['signature_date'] = { 'month' => '11', 'day' => '21', 'year' => '2026' }
        expect(harness.date_parts_to_string(form, 'signature_date')).to eq('11/21/2026')
      end
    end

    context 'with a missing part' do
      it 'returns an empty string when month is missing' do
        data['signature_date'] = { 'day' => '7', 'year' => '2026' }
        expect(harness.date_parts_to_string(form, 'signature_date')).to eq('')
      end

      it 'returns an empty string when day is missing' do
        data['signature_date'] = { 'month' => '4', 'year' => '2026' }
        expect(harness.date_parts_to_string(form, 'signature_date')).to eq('')
      end

      it 'returns an empty string when year is missing' do
        data['signature_date'] = { 'month' => '4', 'day' => '7' }
        expect(harness.date_parts_to_string(form, 'signature_date')).to eq('')
      end
    end

    context 'when the key is missing entirely' do
      let(:data) { {} }

      it 'returns an empty string' do
        expect(harness.date_parts_to_string(form, 'signature_date')).to eq('')
      end
    end

    context 'when date_part raises' do
      before { allow(form).to receive(:date_part).and_raise(StandardError) }

      it 'rescues and returns an empty string' do
        expect(harness.date_parts_to_string(form, 'signature_date')).to eq('')
      end
    end
  end

  describe 'constant maps' do
    it 'BRANCH_MAP is frozen' do
      expect(described_class::BRANCH_MAP).to be_frozen
    end

    it 'CONVEYANCE_MAP is frozen' do
      expect(described_class::CONVEYANCE_MAP).to be_frozen
    end

    it 'BRANCH_MAP covers the expected branches' do
      expect(described_class::BRANCH_MAP.keys).to contain_exactly(
        'ARMY', 'NAVY', 'AIR FORCE', 'MARINE CORPS', 'COAST GUARD',
        'SPACE FORCE', 'NOAA', 'USPHS'
      )
    end

    it 'CONVEYANCE_MAP covers the expected vehicle types' do
      expect(described_class::CONVEYANCE_MAP.keys).to contain_exactly(
        'AUTOMOBILE', 'STATION WAGON', 'VAN', 'TRUCK'
      )
    end
  end
end
