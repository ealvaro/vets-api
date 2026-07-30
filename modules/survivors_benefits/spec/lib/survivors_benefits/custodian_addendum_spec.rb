# frozen_string_literal: true

require 'rails_helper'
require 'survivors_benefits/custodian_addendum'

RSpec.describe SurvivorsBenefits::CustodianAddendum do
  let(:custodian_form) do
    {
      'claimantRelationship' => 'CUSTODIAN_FILING_FOR_CHILD_UNDER_18',
      'filingCustodianFullName' => {
        'first' => 'Jane',
        'middle' => 'Quincy',
        'last' => 'Custodian'
      },
      'childRelationship' => 'Mother',
      'filingCustodianAddress' => {
        'street' => '123 Main St',
        'street2' => 'Apt 4B',
        'city' => 'Springfield',
        'state' => 'IL',
        'postalCode' => '62704',
        'country' => 'USA'
      },
      'filingCustodianEmail' => 'jane.custodian@example.com'
    }
  end

  describe '.remarks' do
    it 'builds a labeled block with the middle name truncated to an initial' do
      expect(described_class.remarks(custodian_form)).to eq(
        <<~REMARKS.chomp
          ALTERNATE SIGNER (CUSTODIAN) INFORMATION
          Custodian name: Jane Q Custodian
          Relationship to child: Mother
          Custodian address: 123 Main St Apt 4B, Springfield IL 62704, USA
          Custodian email: jane.custodian@example.com
        REMARKS
      )
    end

    it 'recognizes the humanized relationship label written by section 2' do
      form = custodian_form.merge('claimantRelationship' => 'CUSTODIAN FILING FOR CHILD UNDER 18')

      expect(described_class.remarks(form)).to include('Custodian name: Jane Q Custodian')
    end

    it 'appends a suffix to the last name' do
      form = custodian_form.deep_dup
      form['filingCustodianFullName']['suffix'] = 'Jr.'

      expect(described_class.remarks(form)).to include('Custodian name: Jane Q Custodian Jr.')
    end

    it 'omits lines whose values are missing but keeps the header' do
      form = {
        'claimantRelationship' => 'CUSTODIAN_FILING_FOR_CHILD_UNDER_18',
        'filingCustodianFullName' => { 'first' => 'Jane', 'last' => 'Custodian' }
      }

      expect(described_class.remarks(form)).to eq(
        "ALTERNATE SIGNER (CUSTODIAN) INFORMATION\nCustodian name: Jane Custodian"
      )
    end

    it 'returns only the header when the custodian is filing but supplied nothing else' do
      form = { 'claimantRelationship' => 'CUSTODIAN_FILING_FOR_CHILD_UNDER_18' }

      expect(described_class.remarks(form)).to eq('ALTERNATE SIGNER (CUSTODIAN) INFORMATION')
    end

    it 'returns nil for a non-custodian relationship' do
      expect(described_class.remarks(custodian_form.merge('claimantRelationship' => 'SURVIVING_SPOUSE'))).to be_nil
    end

    it 'returns nil when the relationship is absent' do
      expect(described_class.remarks({})).to be_nil
      expect(described_class.remarks(nil)).to be_nil
    end

    it 'does not read the item 6R custodian keys, which describe a different person' do
      form = {
        'claimantRelationship' => 'CUSTODIAN_FILING_FOR_CHILD_UNDER_18',
        'custodianFullName' => { 'first' => 'Other', 'last' => 'Custodian' },
        'custodianAddress' => { 'street' => '999 Elsewhere Ave', 'city' => 'Nowhere', 'state' => 'TX' }
      }

      remarks = described_class.remarks(form)

      expect(remarks).not_to include('Other Custodian')
      expect(remarks).not_to include('999 Elsewhere Ave')
    end
  end
end
