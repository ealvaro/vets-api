# frozen_string_literal: true

require 'rails_helper'

RSpec.describe SimpleFormsApi::VBA108678 do
  subject(:form) { described_class.new(data) }

  let(:fixture_file) { 'vba_10_8678.json' }
  let(:fixture_path) do
    Rails.root.join('modules', 'simple_forms_api', 'spec', 'fixtures', 'form_json', fixture_file)
  end
  let(:data) { JSON.parse(fixture_path.read) }

  describe '#address' do
    subject(:address) { form.address }

    it { is_expected.to be_a FormEngine::Address }

    it 'maps correctly to attributes' do
      expect(address.address_line1).to eq data.dig('address', 'street')
      expect(address.address_line2).to eq data.dig('address', 'street2')
      expect(address.city).to eq data.dig('address', 'city')
      expect(address.state_code).to eq data.dig('address', 'state')
      expect(address.zip_code).to eq data.dig('address', 'postal_code')
    end
  end

  describe '#name_for_pdf' do
    subject { form.name_for_pdf }

    it 'returns the veteran full name as last, first, middle initial' do
      expect(subject).to eq 'Doe, John, D'
    end
  end

  describe '#last_four_ssn' do
    subject { form.last_four_ssn }

    it 'splits SSN into three parts' do
      expect(subject).to eq('6789')
    end
  end

  describe '#notification_email_address' do
    subject { form.notification_email_address }

    it 'returns the email from data' do
      expect(subject).to eq data['emailAddress']
    end
  end

  describe '#signature' do
    subject { form.signature }

    it 'returns the veteran signature' do
      expect(subject).to eq data['veteranSignature']
    end
  end

  describe '#appliances' do
    subject { form.appliances }

    it 'returns appliances array from data or empty array' do
      expect(subject).to eq(data['appliances'])
    end
  end

  describe '#map_appliances' do
    subject { form.map_appliances }

    it 'maps appliance data correctly for PDF' do
      first_appliance = subject[0]
      raw_appliance = data['appliances'][0]

      expect(first_appliance[:device]).to eq(raw_appliance['deviceOrMedication'])
      expect(first_appliance[:disability]).to eq(raw_appliance['serviceConnectedDisability'])
      expect(first_appliance[:upper_or_lower]).to eq(
        { upper: 1, upper_side: 'LEFT', lower: 'Off', lower_side: 'Off' }
      )
      expect(subject[1][:upper_or_lower]).to eq(
        { upper: 'Off', upper_side: 'Off', lower: 2, lower_side: 'RIGHT' }
      )
      expect(subject[2][:upper_or_lower]).to eq(
        { upper: 1, upper_side: 'RIGHT', lower: 'Off', lower_side: 'Off' }
      )
      expect(subject[3][:upper_or_lower]).to eq(
        { upper: 'Off', upper_side: 'Off', lower: 2, lower_side: 'LEFT' }
      )
    end
  end

  describe '#metadata' do
    subject { form.metadata }

    it 'returns the proper hash' do
      expect(subject).to eq(
        {
          'veteranFirstName' => data.dig('fullName', 'first'),
          'veteranLastName' => data.dig('fullName', 'last'),
          'zipCode' => data.dig('address', 'zip_code'),
          'source' => 'VA Platform Digital Forms',
          'docType' => data['form_number'],
          'businessLine' => 'CMP'
        }
      )
    end
  end
end
