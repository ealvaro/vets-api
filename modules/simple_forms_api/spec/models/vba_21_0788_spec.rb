# frozen_string_literal: true

require 'rails_helper'

RSpec.describe SimpleFormsApi::VBA210788 do
  subject(:form) { described_class.new(data) }

  let(:fixture_file) { 'vba_21_0788.json' }

  let(:fixture_path) do
    Rails.root.join(
      'modules',
      'simple_forms_api',
      'spec',
      'fixtures',
      'form_json',
      fixture_file
    )
  end

  let(:data) { JSON.parse(fixture_path.read) }

  describe '#data' do
    subject { form.data }

    it { is_expected.to match(data) }
  end

  describe '#address' do
    subject(:address) { form.address }

    it { is_expected.to be_a(FormEngine::Address) }

    it 'maps correctly' do
      expect(address.address_line1).to eq data.dig('address', 'street')
      expect(address.address_line2).to eq data.dig('address', 'street2')
      expect(address.city).to eq data.dig('address', 'city')
      expect(address.state_code).to eq data.dig('address', 'state')
      expect(address.zip_code).to eq data.dig('address', 'postal_code')
      expect(address.country_code_iso3).to eq data.dig('address', 'country')
    end
  end

  describe '#full_name' do
    subject { form.full_name }

    it 'joins name parts' do
      expect(subject).to eq(
        [
          data.dig('full_name', 'first'),
          data.dig('full_name', 'middle'),
          data.dig('full_name', 'last')
        ].compact.join(' ')
      )
    end
  end

  describe '#full_address' do
    subject { form.full_address }

    it 'joins address parts with commas and removes nil values' do
      expect(subject).to eq(
        [
          form.address.address_line1,
          form.address.address_line2,
          form.address.city,
          form.address.state_code,
          form.address.zip_code
        ].compact.join(', ')
      )
    end
  end

  describe '#ssn' do
    subject { form.ssn }

    it { is_expected.to eq data['ssn'] }
  end

  describe '#file_number' do
    subject { form.file_number }

    it { is_expected.to eq data['va_file_number'] }
  end

  describe '#relationship' do
    subject { form.relationship }

    it { is_expected.to eq data['relationship_to_veteran'] }
  end

  describe '#phone' do
    subject { form.phone }

    it { is_expected.to match(/\d{3}-\d{3}-\d{4}/) }
  end

  describe '#email' do
    subject { form.email }

    it { is_expected.to eq data['email'] }
  end

  describe '#legally_adopted?' do
    subject { form.legally_adopted? }

    it { is_expected.to eq data['legally_adopted'] }
  end

  describe '#stepchild_living_in_household?' do
    subject { form.stepchild_living_in_household? }

    it { is_expected.to eq data['stepchild_living_in_household'] }
  end

  describe 'INCARCERATION_BLOCKS' do
    it 'has correct mapping for veteran incarcerated' do
      expect(described_class::INCARCERATION_BLOCKS[:veteran_incarcerated]).to eq(
        {
          main: 2,
          felony: 3,
          misdemeanor: 4
        }
      )
    end

    it 'has correct mapping for spouse or child incarcerated' do
      expect(described_class::INCARCERATION_BLOCKS[:spouse_or_child_incarcerated]).to eq(
        {
          main: 5,
          felony: 6,
          misdemeanor: 7
        }
      )
    end
  end

  describe 'SINGLE_REASONS' do
    it 'matches expected mapping' do
      expect(described_class::SINGLE_REASONS).to eq(
        {
          veteran_incompetent_no_fiduciary: 8,
          veteran_pension_care_facility: 9,
          enemy_territory_resident: 10,
          veteran_disappeared: 11
        }
      )
    end
  end

  describe '#incarceration_fields' do
    subject(:result) { form.incarceration_fields }

    context 'veteran incarcerated with felony and misdemeanor' do
      let(:data) do
        super().merge(
          'reason' => 'veteran_incarcerated',
          'incarceration' => {
            'felony' => true,
            'misdemeanor' => true
          }
        )
      end

      it 'sets veteran incarceration block correctly' do
        expect(result).to include(
          'form1[0].Page_2[0].RadioButtonList[2]' => '0',
          'form1[0].Page_2[0].RadioButtonList[3]' => '0',
          'form1[0].Page_2[0].RadioButtonList[4]' => '0'
        )
      end
    end

    context 'spouse or child incarcerated without felony/misdemeanor' do
      let(:data) do
        super().merge(
          'reason' => 'spouse_or_child_incarcerated',
          'incarceration' => {
            'felony' => false,
            'misdemeanor' => false
          }
        )
      end

      it 'sets spouse/child block correctly' do
        expect(result).to include(
          'form1[0].Page_2[0].RadioButtonList[5]' => '0',
          'form1[0].Page_2[0].RadioButtonList[6]' => 'Off',
          'form1[0].Page_2[0].RadioButtonList[7]' => 'Off'
        )
      end
    end

    context 'single reason: veteran disappeared' do
      let(:data) do
        super().merge('reason' => 'veteran_disappeared')
      end

      it 'sets correct single reason radio' do
        expect(result).to include(
          'form1[0].Page_2[0].RadioButtonList[11]' => '0'
        )
      end
    end
  end

  describe '#facility_name' do
    subject { form.facility_name }

    it { is_expected.to eq data['facility_name'] }
  end

  describe '#facility_address' do
    subject { form.facility_address }

    it { is_expected.to eq data['facility_address'] }
  end

  describe '#remarks' do
    subject { form.remarks }

    it { is_expected.to eq data['remarks'] }
  end

  describe '#signature' do
    subject { form.signature }

    it { is_expected.to eq data['statement_of_truth_signature'] }
  end

  describe '#signature_date' do
    subject { form.signature_date }

    context 'when present' do
      it { is_expected.to match(%r{\d{2}/\d{2}/\d{4}}) }
    end

    context 'when missing' do
      let(:data) { super().merge('signature_date' => nil) }

      it { is_expected.to be_nil }
    end
  end

  describe '#metadata' do
    subject { form.metadata }

    it 'returns expected structure' do
      expect(subject).to include(
        'veteranFullName' => form.full_name,
        'fileNumber' => form.file_number,
        'source' => 'VA Platform Digital Forms',
        'docType' => "StructuredData:#{data['form_number']}",
        'businessLine' => 'CMP'
      )
    end
  end

  describe '#format_phone' do
    it 'formats phone correctly' do
      expect(form.format_phone('1234567890')).to eq('123-456-7890')
    end
  end
end
