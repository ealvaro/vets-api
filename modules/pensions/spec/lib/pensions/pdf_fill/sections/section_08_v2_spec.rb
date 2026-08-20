# frozen_string_literal: true

require 'rails_helper'
require 'pensions/pdf_fill/sections/section_08_v2'

describe Pensions::PdfFill::Section8V2 do
  describe '#expand' do
    subject(:expand) { described_class.new.expand(form_data) }

    let(:form_data) do
      {
        'dependents' => [
          {
            'childInHousehold' => true,
            'childPlaceOfBirth' => 'Tallahassee, FL',
            'childSocialSecurityNumber' => '333224444',
            'childRelationship' => 'BIOLOGICAL',
            'previouslyMarried' => false,
            'disabled' => false,
            'married' => false,
            'fullName' => {
              'first' => 'Sasquatch',
              'middle' => 'Maria',
              'last' => 'Moustaches-de-chat'
            },
            'childDateOfBirth' => '2000-01-31'
          },
          {
            'childInHousehold' => false,
            'childAddress' => {
              'street' => '123 8th st',
              'city' => 'Hadley',
              'country' => 'USA',
              'state' => 'ME',
              'postalCode' => '01050'
            },
            'personWhoLivesWithChild' => {
              'first' => 'Ranch',
              'middle' => 'Mustard',
              'last' => 'Michaels'
            },
            'childPlaceOfBirth' => 'Tallahassee, FL',
            'childSocialSecurityNumber' => '333224445',
            'childRelationship' => 'STEP_CHILD',
            'previouslyMarried' => false,
            'disabled' => false,
            'married' => false,
            'fullName' => {
              'first' => 'Princess',
              'middle' => 'Gargoyle',
              'last' => 'Filibuster'
            },
            'childDateOfBirth' => '1993-01-31'
          },
          {
            'childInHousehold' => false,
            'childAddress' => {
              'street' => '123 8th st',
              'city' => 'Hadley',
              'country' => 'USA',
              'state' => 'ME',
              'postalCode' => '01050'
            },
            'personWhoLivesWithChild' => {
              'first' => 'Ranch',
              'middle' => 'Mustard',
              'last' => 'Michaels'
            },
            'childPlaceOfBirth' => 'Tallahassee, FL',
            'childSocialSecurityNumber' => '333224445',
            'childRelationship' => 'ADOPTED',
            'previouslyMarried' => false,
            'disabled' => false,
            'married' => false,
            'fullName' => {
              'first' => 'Triangulon',
              'middle' => 'Gottfried',
              'last' => 'Withersponge'
            },
            'childDateOfBirth' => '1995-01-31'
          },
          {
            'childInHousehold' => false,
            'childAddress' => {
              'street' => '100 Main St',
              'city' => 'Kalispell',
              'country' => 'USA',
              'state' => 'MT',
              'postalCode' => '59901'
            },
            'personWhoLivesWithChild' => {
              'first' => 'Carl',
              'middle' => 'Michael',
              'last' => 'Carlmichael'
            },
            'childPlaceOfBirth' => 'Tallahassee, FL',
            'childSocialSecurityNumber' => '333224445',
            'childRelationship' => 'STEP_CHILD',
            'previouslyMarried' => false,
            'disabled' => false,
            'married' => false,
            'fullName' => {
              'first' => 'Persephone',
              'middle' => 'Melanie',
              'last' => 'Munchkin'
            },
            'childDateOfBirth' => '1995-01-31'
          }
        ]
      }
    end

    it 'returns early if no dependents' do
      form_data = { 'dependents' => [] }
      expect(described_class.new.expand(form_data)).to be_nil
    end

    it 'counts the number of dependents living in household' do
      expand
      expect(form_data['dependentChildrenInHousehold']).to eq(1)
    end

    it 'flags when dependents who do not live with veteran live in different households' do
      expand
      expect(form_data['dependentsNotWithYouAtSameAddress']).to eq(1) # radio value 'No'
    end

    it 'flags when dependents who live with veteran live in same household' do
      form_data['dependents'].pop
      expand
      expect(form_data['dependentsNotWithYouAtSameAddress']).to eq(0) # radio value 'Yes'
    end

    it 'associates multiple dependents with same custodian but does not list the custodian multiple times' do
      form_data['dependents'].pop
      expand
      expect(form_data['custodians'].size).to eq(1)
      custodian = form_data['custodians'].first
      custodian_name = described_class.new.extract_middle_initial(custodian)
                                      .values_at('first', 'middle', 'last').compact.join(' ')
      expect(form_data['dependents'].third['personWhoLivesWithChild']).to eq(custodian_name)
      expect(form_data['dependents'].third['personWhoLivesWithChild']).to eq(custodian_name)
    end

    it 'does not expand custodians if dependent lives in household' do
      dependent = form_data['dependents'].second
      dependent['childInHousehold'] = true
      expand
      expect(dependent['personWhoLivesWithChild'].present?).to be true
      expect(form_data['custodians']).not_to include(dependent)
    end

    it 'includes dependent/custodian address if dependent not in household' do
      expand
      expect(form_data['custodians'].first['custodianAddress']).to eq(
        form_data['dependents'].second['childAddress']
      )
    end

    it 'formats dependent/custodian address for overflow' do
      expand
      dependent = form_data['dependents'].second
      address = dependent['childAddress']
      postal_code = address['postalCode'].values.compact_blank.join('-')
      expect(dependent['custodianAddressOverflow']).to eq(
        "#{address['street']}\n#{address['city']} #{address['state']} #{postal_code}\n#{address['country']}"
      )
    end

    it 'formats dependent name for overflow' do
      expand
      dependent = form_data['dependents'].first
      expect(dependent['fullNameOverflow']).to eq(dependent['fullName'].values.compact.join(' '))
    end

    it 'formats dependent status for overflow' do
      dependent = form_data['dependents'].second
      expand
      expect(dependent['childStatusOverflow']).to eq('Step child, does not live with you but contributes')
    end
  end
end
