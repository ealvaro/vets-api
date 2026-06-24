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
      expect(subject).to eq data['email_address']
    end
  end

  describe '#signature' do
    subject { form.signature }

    it 'returns the veteran signature' do
      expect(subject).to eq data['veteran_signature']
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

      expect(first_appliance[:device]).to eq(raw_appliance['device_or_medication'])
      expect(first_appliance[:disability]).to eq(raw_appliance['service_connected_disability'])
      expect(first_appliance[:impacted_locations]).to eq(
        { upper_left: true, upper_right: false, lower_left: false, lower_right: false }
      )
      expect(subject[1][:impacted_locations]).to eq(
        { upper_left: false, upper_right: false, lower_left: false, lower_right: true }
      )
      expect(subject[2][:impacted_locations]).to eq(
        { upper_left: false, upper_right: true, lower_left: false, lower_right: false }
      )
      expect(subject[3][:impacted_locations]).to eq(
        { upper_left: false, upper_right: false, lower_left: true, lower_right: false }
      )
    end
  end

  describe '#manual_fills' do
    let(:pdf_path) { 'tmp/test-vba_10_8678.pdf' }
    let(:doc) { instance_double(HexaPDF::Document) }
    let(:page) { instance_double(HexaPDF::Type::Page) }
    let(:canvas) { instance_double(HexaPDF::Content::Canvas) }

    it 'draws an x for each selected location without collapsing multi-select values' do
      data['appliances'][0]['impacted_locations'] = {
        'upper_left' => true,
        'upper_right' => true,
        'lower_left' => true,
        'lower_right' => true
      }

      allow(HexaPDF::Document).to receive(:open).with(pdf_path).and_return(doc)
      allow(doc).to receive(:pages).and_return([page])
      allow(page).to receive(:canvas).with(type: :overlay).and_return(canvas)
      allow(canvas).to receive(:save_graphics_state).and_yield
      allow(canvas).to receive(:fill_color)
      allow(canvas).to receive(:font)
      allow(canvas).to receive(:text)
      allow(doc).to receive(:write)
      allow(FileUtils).to receive(:mv)
      allow(Common::FileHelpers).to receive(:delete_file_if_exists)

      form.manual_fills(pdf_path)

      expect(canvas).to have_received(:text).with('x', at: [313.5, 304.0])
      expect(canvas).to have_received(:text).with('x', at: [313.5, 291.5])
      expect(canvas).to have_received(:text).with('x', at: [361.5, 291.5])
      expect(canvas).to have_received(:text).with('x', at: [451.5, 304.0])
      expect(canvas).to have_received(:text).with('x', at: [451.5, 291.5])
      expect(canvas).to have_received(:text).with('x', at: [499.5, 291.5])
      expect(canvas).to have_received(:text).with('x', at: [451.5, 268.0])
      expect(canvas).to have_received(:text).with('x', at: [499.5, 255.5])
      expect(canvas).to have_received(:text).with('x', at: [313.5, 232.0])
      expect(canvas).to have_received(:text).with('x', at: [361.5, 219.5])
      expect(canvas).to have_received(:text).with('x', at: [451.5, 196.0])
      expect(canvas).to have_received(:text).with('x', at: [451.5, 183.5])
    end
  end

  describe '#overflow_pdf' do
    it 'creates an overflow page for multi-select impacted locations' do
      data['appliances'][0]['impacted_locations'] = {
        'upper_left' => true,
        'upper_right' => true,
        'lower_left' => true,
        'lower_right' => true
      }

      overflow_generator = instance_double(SimpleFormsApi::Overflow108678, generate: '/tmp/overflow.pdf')

      expect(SimpleFormsApi::Overflow108678).to receive(:new).with(
        data['appliances'],
        cutoff: 1
      ).and_return(overflow_generator)

      expect(form.overflow_pdf).to eq('/tmp/overflow.pdf')
    end
  end

  describe '#metadata' do
    subject { form.metadata }

    it 'returns the proper hash with bug fix off' do
      allow(Flipper).to receive(:enabled?).with(:simple_forms_s3_mms_prefix_bugfix).and_return(false)
      expect(subject).to eq(
        {
          'veteranFirstName' => data.dig('full_name', 'first'),
          'veteranLastName' => data.dig('full_name', 'last'),
          'zipCode' => data.dig('address', 'postal_code'),
          'fileNumber' => data['va_file_number'].presence || data['ssn'],
          'source' => 'VA Platform Digital Forms',
          'docType' => data['form_number'],
          'businessLine' => 'CMP'
        }
      )
    end

    it 'returns the proper hash with bug fix on' do
      allow(Flipper).to receive(:enabled?).with(:simple_forms_s3_mms_prefix_bugfix).and_return(true)
      expect(subject).to eq(
        {
          'veteranFirstName' => data.dig('full_name', 'first'),
          'veteranLastName' => data.dig('full_name', 'last'),
          'zipCode' => data.dig('address', 'postal_code'),
          'fileNumber' => data['va_file_number'].presence || data['ssn'],
          'source' => 'VA Platform Digital Forms',
          'docType' => 'StructuredData:10-8678',
          'businessLine' => 'CMP'
        }
      )
    end
  end

  describe '#track_user_identity' do
    before do
      allow(StatsD).to receive(:increment)
      allow(Rails.logger).to receive(:info)
    end

    context 'when user is terminating' do
      let(:data) do
        {
          'elect_termination' => true
        }
      end

      it 'tracks employed identity and logs information' do
        described_class.new(data).track_user_identity('ABC123')

        expect(StatsD).to have_received(:increment).with('api.simple_forms_api.10_8678.terminating')
        expect(Rails.logger).to have_received(:info).with(
          'Simple forms api - 10-8678 submission user identity',
          identity: 'terminating',
          confirmation_number: 'ABC123'
        )
      end
    end

    context 'when user is applying' do
      let(:data) do
        {
          'elect_termination' => false
        }
      end

      it 'tracks unemployed identity and logs information' do
        described_class.new(data).track_user_identity('XYZ789')

        expect(StatsD).to have_received(:increment).with('api.simple_forms_api.10_8678.applying')
        expect(Rails.logger).to have_received(:info).with(
          'Simple forms api - 10-8678 submission user identity',
          identity: 'applying',
          confirmation_number: 'XYZ789'
        )
      end
    end
  end
end
