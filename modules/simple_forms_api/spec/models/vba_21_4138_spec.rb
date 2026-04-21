# frozen_string_literal: true

require 'rails_helper'
require_relative '../support/shared_examples_for_base_form'

RSpec.describe SimpleFormsApi::VBA214138 do
  describe '#zip_code_is_us_based' do
    context 'when Veteran is filing with profile mailing address' do
      it 'returns true for USA' do
        data = {
          'claimant_type' => 'self',
          'veteran' => { 'mailing_address' => { 'country_code_iso3' => 'USA' } }
        }
        expect(described_class.new(data).zip_code_is_us_based).to be true
      end

      it 'returns false for non-USA' do
        data = {
          'claimant_type' => 'self',
          'veteran' => { 'mailing_address' => { 'country_code_iso3' => 'CAN' } }
        }
        expect(described_class.new(data).zip_code_is_us_based).to be false
      end
    end

    context 'when non-Veteran is filing with veteran_mailing_address' do
      it 'returns true for USA' do
        data = {
          'claimant_type' => 'forVeteran',
          'veteran_mailing_address' => { 'country' => 'USA' }
        }
        expect(described_class.new(data).zip_code_is_us_based).to be true
      end

      it 'returns false for non-USA' do
        data = {
          'claimant_type' => 'forVeteran',
          'veteran_mailing_address' => { 'country' => 'CAN' }
        }
        expect(described_class.new(data).zip_code_is_us_based).to be false
      end
    end
  end

  describe '#desired_stamps' do
    let(:data) { { 'statement_of_truth_signature' => 'John Doe' } }

    it 'returns signature stamp with coordinates' do
      result = described_class.new(data).desired_stamps
      expect(result).to be_an(Array)
      expect(result.first[:coords]).to eq([[35, 220]])
      expect(result.first[:text]).to eq('John Doe')
      expect(result.first[:page]).to eq(1)
    end
  end

  describe '#submission_date_stamps' do
    let(:data) { {} }
    let(:timestamp) { Time.zone.parse('2023-05-15 10:30:00 UTC') }

    it 'returns submission date stamps' do
      result = described_class.new(data).submission_date_stamps(timestamp)
      expect(result).to be_an(Array)
      expect(result.length).to eq(2)
      expect(result.first[:text]).to eq('Application Submitted:')
      expect(result.first[:page]).to eq(0)
      expect(result.last[:text]).to include('UTC')
      expect(result.last[:page]).to eq(0)
    end
  end

  describe '#metadata' do
    context 'when a non-Veteran is filing' do
      let(:data) do
        {
          'claimant_type' => 'forVeteran',
          'veteran_full_name' => { 'first' => 'John', 'last' => 'Lawrence' },
          'veteran_id_number' => { 'ssn' => '432959594' },
          'veteran_mailing_address' => { 'postal_code' => '46375' },
          'full_name' => { 'first' => 'Ally', 'last' => 'Soto' },
          'form_number' => '21-4138'
        }
      end

      it 'uses the Veterans name and ID in metadata' do
        result = described_class.new(data).metadata
        expect(result['veteranFirstName']).to eq('John')
        expect(result['veteranLastName']).to eq('Lawrence')
        expect(result['fileNumber']).to eq('432959594')
        expect(result['zipCode']).to eq('46375')
        expect(result['source']).to eq('VA Platform Digital Forms')
        expect(result['docType']).to eq('21-4138')
        expect(result['businessLine']).to eq('CMP')
      end
    end

    context 'when the Veteran is filing' do
      context 'with top-level profile keys and profile mailing address' do
        let(:data) do
          {
            'claimant_type' => 'self',
            'first' => 'John',
            'last' => 'Veteran',
            'id_number' => { 'ssn' => '321540987' },
            'veteran' => {
              'mailing_address' => {
                'address_line1' => '400 NW 65th St',
                'city' => 'Seattle',
                'state_code' => 'WA',
                'zip_code' => '98117',
                'country_code_iso3' => 'USA'
              }
            },
            'form_number' => '21-4138'
          }
        end

        it 'uses the Veterans name, ID, and profile mailing address in metadata' do
          result = described_class.new(data).metadata
          expect(result['veteranFirstName']).to eq('John')
          expect(result['veteranLastName']).to eq('Veteran')
          expect(result['fileNumber']).to eq('321540987')
          expect(result['zipCode']).to eq('98117')
          expect(result['source']).to eq('VA Platform Digital Forms')
          expect(result['docType']).to eq('21-4138')
          expect(result['businessLine']).to eq('CMP')
        end
      end

      it 'uses VA file number when available' do
        data = {
          'claimant_type' => 'self',
          'first' => 'John',
          'last' => 'Veteran',
          'id_number' => { 'va_file_number' => 'C12345678', 'ssn' => '321540987' },
          'veteran' => { 'mailing_address' => { 'zip_code' => '98117', 'country_code_iso3' => 'USA' } },
          'form_number' => '21-4138'
        }
        result = described_class.new(data).metadata
        expect(result['fileNumber']).to eq('C12345678')
      end

      it 'falls back to SSN when VA file number is blank' do
        data = {
          'claimant_type' => 'self',
          'first' => 'John',
          'last' => 'Veteran',
          'id_number' => { 'va_file_number' => '', 'ssn' => '321540987' },
          'veteran' => { 'mailing_address' => { 'zip_code' => '98117', 'country_code_iso3' => 'USA' } },
          'form_number' => '21-4138'
        }
        result = described_class.new(data).metadata
        expect(result['fileNumber']).to eq('321540987')
      end
    end
  end

  describe '#veteran_full_name' do
    context 'when non-Veteran is filing' do
      let(:data) do
        {
          'claimant_type' => 'forVeteran',
          'veteran_full_name' => { 'first' => 'John', 'middle' => 'Dear', 'last' => 'Lawrence' },
          'full_name' => { 'first' => 'Ally', 'last' => 'Soto' }
        }
      end

      it 'returns veteran_full_name' do
        expect(described_class.new(data).veteran_full_name).to eq({
                                                                    'first' => 'John',
                                                                    'middle' => 'Dear',
                                                                    'last' => 'Lawrence'
                                                                  })
      end
    end

    context 'when Veteran is filing' do
      context 'with top-level profile keys' do
        let(:data) do
          {
            'claimant_type' => 'self',
            'first' => 'John',
            'last' => 'Veteran'
          }
        end

        it 'returns name from top-level keys' do
          expect(described_class.new(data).veteran_full_name).to eq({
                                                                      'first' => 'John',
                                                                      'last' => 'Veteran'
                                                                    })
        end
      end

      context 'when top-level keys are absent, falls back to full_name' do
        let(:data) do
          {
            'claimant_type' => 'self',
            'full_name' => { 'first' => 'John', 'last' => 'Veteran' }
          }
        end

        it 'falls back to full_name' do
          expect(described_class.new(data).veteran_full_name).to eq({
                                                                      'first' => 'John',
                                                                      'last' => 'Veteran'
                                                                    })
        end
      end

      context 'when veteran_full_name is an empty hash' do
        let(:data) do
          {
            'claimant_type' => 'self',
            'veteran_full_name' => {},
            'full_name' => { 'first' => 'John', 'last' => 'Veteran' }
          }
        end

        it 'falls back to full_name' do
          expect(described_class.new(data).veteran_full_name).to eq({
                                                                      'first' => 'John',
                                                                      'last' => 'Veteran'
                                                                    })
        end
      end
    end
  end

  describe '#veteran_id_data' do
    context 'when veteran_id_number is present (non-Veteran filer)' do
      let(:data) do
        {
          'veteran_id_number' => { 'ssn' => '432959594' },
          'id_number' => { 'ssn' => '999999999' }
        }
      end

      it 'returns veteran_id_number' do
        expect(described_class.new(data).veteran_id_data).to eq({ 'ssn' => '432959594' })
      end
    end

    context 'when veteran_id_number is absent (Veteran filer)' do
      let(:data) { { 'id_number' => { 'ssn' => '321540987' } } }

      it 'falls back to id_number' do
        expect(described_class.new(data).veteran_id_data).to eq({ 'ssn' => '321540987' })
      end
    end
  end

  describe '#veteran_mailing_address' do
    context 'when non-Veteran is filing' do
      it 'returns veteran_mailing_address directly' do
        data = {
          'claimant_type' => 'forVeteran',
          'veteran_mailing_address' => { 'street' => '123 Fake St', 'city' => 'Faketown', 'state' => 'IN',
                                         'postal_code' => '46375', 'country' => 'USA' }
        }
        expect(described_class.new(data).veteran_mailing_address).to eq({
                                                                          'street' => '123 Fake St',
                                                                          'city' => 'Faketown',
                                                                          'state' => 'IN',
                                                                          'postal_code' => '46375',
                                                                          'country' => 'USA'
                                                                        })
      end
    end

    context 'when Veteran is filing with profile mailing address' do
      it 'parses the profile mailing address into the expected shape' do
        data = {
          'claimant_type' => 'self',
          'veteran' => {
            'mailing_address' => {
              'address_line1' => '400 NW 65th St',
              'city' => 'Seattle',
              'state_code' => 'WA',
              'zip_code' => '98117',
              'country_code_iso3' => 'USA'
            }
          }
        }
        expect(described_class.new(data).veteran_mailing_address).to eq({
                                                                          'street' => '400 NW 65th St',
                                                                          'city' => 'Seattle',
                                                                          'state' => 'WA',
                                                                          'postal_code' => '98117',
                                                                          'country' => 'USA'
                                                                        })
      end
    end

    context 'when no address is present' do
      it 'returns an empty hash' do
        expect(described_class.new({}).veteran_mailing_address).to eq({})
      end
    end
  end

  describe '#veteran_phone' do
    context 'when non-Veteran is filing' do
      it 'returns veteran_phone directly' do
        data = { 'veteran_phone' => '2197756113' }
        expect(described_class.new(data).veteran_phone).to eq('2197756113')
      end
    end

    context 'when Veteran is filing with profile mobile phone' do
      it 'concatenates area_code and phone_number' do
        data = {
          'veteran' => {
            'mobile_phone' => { 'area_code' => '123', 'phone_number' => '4567890' }
          }
        }
        expect(described_class.new(data).veteran_phone).to eq('1234567890')
      end
    end

    context 'when no phone is present' do
      it 'returns nil' do
        expect(described_class.new({}).veteran_phone).to be_nil
      end
    end
  end

  describe '#veteran_email' do
    context 'when non-Veteran is filing' do
      it 'returns veteran_email_address directly' do
        data = { 'veteran_email_address' => 'veteran@example.com' }
        expect(described_class.new(data).veteran_email).to eq('veteran@example.com')
      end
    end

    context 'when Veteran is filing with profile email' do
      it 'returns email from nested veteran object' do
        data = { 'veteran' => { 'email' => { 'email_address' => 'testing@gmail.com' } } }
        expect(described_class.new(data).veteran_email).to eq('testing@gmail.com')
      end
    end

    context 'when no email is present' do
      it 'returns nil' do
        expect(described_class.new({}).veteran_email).to be_nil
      end
    end
  end

  describe '#veteran_date_of_birth' do
    context 'when non-Veteran is filing' do
      it 'returns veteran_date_of_birth directly' do
        data = { 'veteran_date_of_birth' => '1980-04-01' }
        expect(described_class.new(data).veteran_date_of_birth).to eq('1980-04-01')
      end
    end

    context 'when Veteran is filing' do
      it 'returns date_of_birth' do
        data = { 'date_of_birth' => '1980-01-01' }
        expect(described_class.new(data).veteran_date_of_birth).to eq('1980-01-01')
      end
    end

    context 'when no date of birth is present' do
      it 'returns nil' do
        expect(described_class.new({}).veteran_date_of_birth).to be_nil
      end
    end
  end

  describe '#notification_first_name' do
    context 'when a non-veteran claimant is filing' do
      let(:data) { { 'full_name' => { 'first' => 'John', 'last' => 'Doe' } } }

      it 'returns the first name from full_name' do
        expect(described_class.new(data).notification_first_name).to eq('John')
      end
    end

    context 'when the veteran is filing for themselves' do
      let(:data) { { 'claimant_type' => 'self', 'first' => 'John', 'last' => 'Veteran' } }

      it 'returns the first name from the top-level key' do
        expect(described_class.new(data).notification_first_name).to eq('John')
      end
    end
  end

  describe '#notification_email_address' do
    context 'when the veteran is filing' do
      it 'returns email from the nested veteran object' do
        data = { 'claimant_type' => 'self', 'veteran' => { 'email' => { 'email_address' => 'veteran@example.com' } } }
        expect(described_class.new(data).notification_email_address).to eq('veteran@example.com')
      end

      it 'returns veteran_email_address when nested veteran email is absent' do
        data = { 'claimant_type' => 'self', 'veteran_email_address' => 'veteran@example.com' }
        expect(described_class.new(data).notification_email_address).to eq('veteran@example.com')
      end
    end

    context 'when a non-veteran claimant is filing' do
      it 'returns veteran_email_address' do
        data = { 'claimant_type' => 'forVeteran', 'veteran_email_address' => 'veteran@example.com' }
        expect(described_class.new(data).notification_email_address).to eq('veteran@example.com')
      end
    end

    context 'when no email is present' do
      it 'returns nil' do
        expect(described_class.new({}).notification_email_address).to be_nil
      end
    end
  end

  describe '#overflow_pdf' do
    context 'when statement is within the character limit' do
      let(:data) do
        {
          'claimant_type' => 'self',
          'statement' => 'a' * 3685,
          'first' => 'John',
          'last' => 'Veteran',
          'id_number' => { 'ssn' => '321540987' }
        }
      end

      it 'returns nil' do
        expect(described_class.new(data).overflow_pdf).to be_nil
      end
    end

    context 'when statement exceeds the character limit' do
      let(:data) do
        {
          'claimant_type' => 'self',
          'statement' => 'a' * 4000,
          'first' => 'John',
          'last' => 'Veteran',
          'id_number' => { 'ssn' => '321540987' }
        }
      end

      it 'creates a PDF file' do
        result = described_class.new(data).overflow_pdf
        expect(result).to be_a(String)
        expect(File.exist?(result)).to be true
        File.delete(result) if result && File.exist?(result)
      end
    end

    context 'when statement is nil' do
      let(:data) do
        {
          'claimant_type' => 'self',
          'statement' => nil,
          'first' => 'John',
          'last' => 'Veteran',
          'id_number' => { 'ssn' => '321540987' }
        }
      end

      it 'returns nil' do
        expect(described_class.new(data).overflow_pdf).to be_nil
      end
    end
  end

  describe 'constants' do
    it 'defines REMARKS_SLICE_1' do
      expect(described_class::REMARKS_SLICE_1).to eq(0..1510)
    end

    it 'defines REMARKS_SLICE_2' do
      expect(described_class::REMARKS_SLICE_2).to eq(1511..3685)
    end

    it 'defines ALLOTTED_REMARKS_LAST_INDEX' do
      expect(described_class::ALLOTTED_REMARKS_LAST_INDEX).to eq(3685)
    end

    it 'defines CLAIMANT_TYPE_VETERAN' do
      expect(described_class::CLAIMANT_TYPE_VETERAN).to eq('self')
    end
  end

  describe '#remarks_with_claimant_header' do
    context 'when the Veteran is filing (claimant_type: self)' do
      let(:data) do
        {
          'claimant_type' => 'self',
          'statement' => 'Some statement text.',
          'full_name' => { 'first' => 'John', 'last' => 'Veteran' }
        }
      end

      it 'returns the statement unchanged with no header' do
        expect(described_class.new(data).remarks_with_claimant_header).to eq('Some statement text.')
      end
    end

    context 'when a non-Veteran is filing (claimant_type: forVeteran)' do
      let(:data) do
        {
          'claimant_type' => 'forVeteran',
          'statement' => 'Some statement text.',
          'full_name' => { 'first' => 'Ally', 'last' => 'Soto' },
          'relationship_to_veteran' => 'spouse'
        }
      end

      it 'prepends the claimant header to the statement' do
        result = described_class.new(data).remarks_with_claimant_header
        expect(result).to start_with('Submitted by: Ally Soto (spouse)')
        expect(result).to include('Some statement text.')
      end
    end

    context 'when relationship is notListed' do
      let(:data) do
        {
          'claimant_type' => 'forVeteran',
          'statement' => 'Some statement text.',
          'full_name' => { 'first' => 'Ally', 'last' => 'Soto' },
          'relationship_to_veteran' => 'notListed',
          'relationship_to_veteran_other' => 'ex wife'
        }
      end

      it 'uses the other relationship description' do
        result = described_class.new(data).remarks_with_claimant_header
        expect(result).to start_with('Submitted by: Ally Soto (ex wife)')
      end
    end

    context 'when statement is nil' do
      let(:data) do
        {
          'claimant_type' => 'forVeteran',
          'statement' => nil,
          'full_name' => { 'first' => 'Ally', 'last' => 'Soto' },
          'relationship_to_veteran' => 'spouse'
        }
      end

      it 'does not raise and still includes the header' do
        result = described_class.new(data).remarks_with_claimant_header
        expect(result).to start_with('Submitted by: Ally Soto (spouse)')
      end
    end

    context 'when name fields are missing' do
      let(:data) do
        {
          'claimant_type' => 'forVeteran',
          'statement' => 'Some statement text.',
          'full_name' => {},
          'relationship_to_veteran' => 'spouse'
        }
      end

      it 'falls back to Not provided for the name' do
        result = described_class.new(data).remarks_with_claimant_header
        expect(result).to start_with('Submitted by: Not provided (spouse)')
      end
    end
  end

  describe '#words_to_remove' do
    context 'when the Veteran is filing' do
      let(:data) do
        {
          'claimant_type' => 'self',
          'id_number' => { 'ssn' => '321540987', 'va_file_number' => 'C12345678' },
          'date_of_birth' => '1980-01-15',
          'veteran' => {
            'mailing_address' => { 'zip_code' => '98117', 'country_code_iso3' => 'USA' },
            'mobile_phone' => { 'area_code' => '206', 'phone_number' => '5550101' },
            'email' => { 'email_address' => 'veteran@example.com' }
          }
        }
      end

      it 'includes SSN parts' do
        result = described_class.new(data).words_to_remove
        expect(result).to include('321', '54', '0987')
      end

      it 'includes VA file number parts' do
        result = described_class.new(data).words_to_remove
        expect(result).to include('C12', '34', '5678')
      end

      it 'includes date of birth parts' do
        result = described_class.new(data).words_to_remove
        expect(result).to include('1980', '01', '15')
      end

      it 'includes postal code' do
        result = described_class.new(data).words_to_remove
        expect(result).to include('98117')
      end

      it 'includes phone number' do
        result = described_class.new(data).words_to_remove
        expect(result).to include('2065550101')
      end

      it 'includes email address' do
        result = described_class.new(data).words_to_remove
        expect(result).to include('veteran@example.com')
      end

      it 'does not include nils' do
        result = described_class.new(data).words_to_remove
        expect(result).not_to include(nil)
      end
    end

    context 'when a non-Veteran is filing' do
      let(:data) do
        {
          'claimant_type' => 'forVeteran',
          'veteran_id_number' => { 'ssn' => '432959594', 'va_file_number' => 'V9876543' },
          'veteran_date_of_birth' => '1955-06-20',
          'veteran_mailing_address' => { 'postal_code' => '46375', 'country' => 'USA' },
          'veteran_phone' => '3175550202',
          'veteran_email_address' => 'nonveteran@example.com'
        }
      end

      it 'uses veteran_id_number SSN parts' do
        result = described_class.new(data).words_to_remove
        expect(result).to include('432', '95', '9594')
      end

      it 'uses veteran_date_of_birth parts' do
        result = described_class.new(data).words_to_remove
        expect(result).to include('1955', '06', '20')
      end

      it 'uses veteran_mailing_address postal code' do
        result = described_class.new(data).words_to_remove
        expect(result).to include('46375')
      end

      it 'uses veteran_phone' do
        result = described_class.new(data).words_to_remove
        expect(result).to include('3175550202')
      end
    end

    context 'when PII fields are absent' do
      it 'returns an array with no nils' do
        result = described_class.new({}).words_to_remove
        expect(result).to be_a(Array)
        expect(result).not_to include(nil)
      end
    end
  end

  context 'when the claimant header pushes content over the limit' do
    let(:header_offset) { 'Submitted by: Ally Soto (spouse)'.length + 2 }
    let(:data) do
      {
        'claimant_type' => 'forVeteran',
        'full_name' => { 'first' => 'Ally', 'last' => 'Soto' },
        'relationship_to_veteran' => 'spouse',
        'statement' => 'a' * 3660,

        'id_number' => { 'ssn' => '123456789' }
      }
    end

    it 'triggers overflow because the header consumes additional characters' do
      form = described_class.new(data)
      expect(form.overflow_pdf).not_to be_nil
    end

    it 'would not trigger overflow without the header' do
      described_class.new(data)
      expect(data['statement'].length).to be < SimpleFormsApi::VBA214138::ALLOTTED_REMARKS_LAST_INDEX
    end

    it 'passes the correct cutoff to the generator accounting for header length' do
      form = described_class.new(data)
      full_remarks = form.remarks_with_claimant_header
      header_length = full_remarks.length - data['statement'].length
      expected_cutoff = [SimpleFormsApi::VBA214138::ALLOTTED_REMARKS_LAST_INDEX - header_length, 0].max

      allow(SimpleFormsApi::OverflowPdfGenerator).to receive(:new).and_call_original
      form.overflow_pdf

      expect(SimpleFormsApi::OverflowPdfGenerator).to have_received(:new).with(
        data,
        cutoff: expected_cutoff
      )
    end
  end
end
