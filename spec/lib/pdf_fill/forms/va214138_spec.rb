# frozen_string_literal: true

require 'rails_helper'
require 'pdf_fill/forms/va214138'

RSpec.describe PdfFill::Forms::Va214138 do
  subject(:form) { described_class.new(base_data) }

  let(:base_data) do
    {
      claimantFullName: { first: 'john', middle: 'q', last: 'doe' },
      veteranSocialSecurityNumber: '123456789',
      veteranDateOfBirth: '1970-01-15',
      claimantPhone: '8005551234',
      claimantAddress: {
        street: '123 Main St',
        city: 'Richmond',
        state: 'VA',
        postalCode: '23220'
      },
      remarks: 'This is a test remark.'
    }
  end

  describe '#merge_fields' do
    subject(:merged) { form.merge_fields }

    it 'titleizes claimant first name' do
      expect(merged['claimantFullName']['first']).to eq('John')
    end

    it 'titleizes claimant last name' do
      expect(merged['claimantFullName']['last']).to eq('Doe')
    end

    it 'uses only middle initial' do
      expect(merged['claimantFullName']['middleInitial']).to eq('Q')
    end

    it 'splits SSN into three parts' do
      ssn = merged['veteranSocialSecurityNumber']
      expect(ssn['first']).to eq('123')
      expect(ssn['second']).to eq('45')
      expect(ssn['third']).to eq('6789')
    end

    it 'copies SSN to page two' do
      expect(merged['pageTwoVeteranSocialSecurityNumber']).to eq(merged['veteranSocialSecurityNumber'])
    end

    it 'splits date of birth' do
      dob = merged['veteranDateOfBirth']
      expect(dob['month']).to eq('01')
      expect(dob['day']).to eq('15')
      expect(dob['year']).to eq('1970')
    end

    it 'splits postal code' do
      postal = merged['claimantAddress']['postalCode']
      expect(postal['firstFive']).to eq('23220')
    end

    it 'expands phone number' do
      phone = merged['claimantPhone']
      expect(phone['phone_area_code']).to eq('800')
      expect(phone['phone_first_three_numbers']).to eq('555')
      expect(phone['phone_last_four_numbers']).to eq('1234')
    end

    it 'returns a hash with string keys' do
      expect(merged.keys).to all(be_a(String))
    end

    context 'with optional fields absent' do
      it 'handles missing middle name gracefully' do
        base_data[:claimantFullName].delete(:middle)
        expect(merged['claimantFullName']['middleInitial']).to be_nil
      end

      it 'handles missing vaFileNumber' do
        expect(merged['vaFileNumber']).to be_nil
      end

      it 'handles missing email' do
        expect(merged['claimantEmailAddress']).to eq({})
      end

      it 'handles missing international phone' do
        expect(merged['claimantInternationalPhone']).to eq('')
      end
    end

    context 'with claimantPhone as a hash' do
      before { base_data[:claimantPhone] = { areaCode: '800', number: '5551234' } }

      it 'coerces phone hash to string before expanding' do
        # to_s on a hash gives "{...}" — confirm it does not raise
        expect { merged }.not_to raise_error
      end
    end
  end

  describe '#merge_email_address' do
    subject { form.merge_email_address(email) }

    context 'with nil email' do
      let(:email) { nil }

      it { is_expected.to eq({}) }
    end

    context 'with empty string' do
      let(:email) { '' }

      it { is_expected.to eq({}) }
    end

    context 'with short email (≤20 chars)' do
      let(:email) { 'user@example.com' }

      it { is_expected.to eq({ first: 'user@example.com' }) }
    end

    context 'with long email (>20 chars)' do
      let(:email) { 'averylongemail@example.com' }

      it 'splits into first and second' do
        result = subject
        expect(result[:first].length).to be <= 20
        expect(result[:second]).to be_present
      end
    end
  end

  describe '#merge_remarks' do
    subject { form.merge_remarks(remarks) }

    context 'with empty remarks' do
      let(:remarks) { '' }

      it { is_expected.to be_nil }
    end

    context 'with short remarks (fits in one chunk)' do
      let(:remarks) { 'Short remark.' }

      it 'returns the remarks verbatim (caller owns any header/formatting)' do
        expect(subject[:remarks]).to eq('Short remark.')
      end

      it 'does not set remarksContinued' do
        expect(subject[:remarksContinued]).to be_nil
      end
    end

    context 'with remarks exceeding 1450 characters' do
      let(:remarks) { 'A' * 1500 }

      it 'sets remarks to the first 1450 chars' do
        expect(subject[:remarks].length).to eq(1450)
      end

      it 'sets remarksContinued with the overflow' do
        expect(subject[:remarksContinued]).to eq('A' * 50)
      end
    end
  end

  describe '#merge_fields remarks propagation' do
    # Regression: merge_fields previously called `form_data.merge(...)` (non-destructive) and
    # discarded the result, so multi-field remarks over 1450 chars never reached the form.
    subject(:merged) { form.merge_fields }

    context 'when remarks overflow the first REMARKS field' do
      before { base_data[:remarks] = 'A' * 1600 }

      it 'propagates the chunked remarks into form_data' do
        expect(merged['remarks'].length).to eq(1450)
        expect(merged['remarksContinued']).to eq('A' * 150)
      end
    end
  end
end
