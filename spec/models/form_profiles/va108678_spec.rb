# frozen_string_literal: true

require 'rails_helper'

RSpec.describe FormProfiles::VA108678 do
  subject(:profile) { described_class.new(form_id: '10-8678', user:) }

  describe '#metadata' do
    let(:user) { create(:user, :loa3, middle_name: 'Aname') }

    it 'returns expected metadata' do
      expect(profile.metadata).to eq(
        {
          version: 0,
          prefill: true,
          returnUrl: '/personal-information'
        }
      )
    end
  end

  describe '#prefill' do
    let(:user) { create(:user, :loa3, middle_name: 'Aname') }

    it 'prefills some user data' do
      data = profile.prefill
      expect(data[:form_data]).to eq(
        {
          'fullName' => { 'first' => 'Abraham', 'middle' => 'A', 'last' => 'Lincoln', 'suffix' => 'Jr.' },
          'ssn' => '796111863',
          'address' => {
            'street' => '140 Rock Creek Rd',
            'city' => 'Washington',
            'state' => 'DC',
            'country' => 'USA',
            'postalCode' => '20011'
          },
          'phone' => '3035551234',
          'emailAddress' => profile.send(:contact_information).email
        }
      )
    end

    context 'with out middle name' do
      let(:user) { create(:user, :loa3) }

      it 'prefills user data w/o middle name' do
        data = profile.prefill
        expect(data[:form_data]).to eq(
          {
            'fullName' => { 'first' => 'Abraham', 'last' => 'Lincoln', 'suffix' => 'Jr.' },
            'ssn' => '796111863',
            'address' => {
              'street' => '140 Rock Creek Rd',
              'city' => 'Washington',
              'state' => 'DC',
              'country' => 'USA',
              'postalCode' => '20011'
            },
            'phone' => '3035551234',
            'emailAddress' => profile.send(:contact_information).email
          }
        )
      end
    end

    context 'with blank middle name' do
      let(:user) { create(:user, :loa3, middle_name: '') }

      it 'prefills user data w/o middle name' do
        data = profile.prefill
        expect(data[:form_data]).to eq(
          {
            'fullName' => { 'first' => 'Abraham', 'last' => 'Lincoln', 'suffix' => 'Jr.' },
            'ssn' => '796111863',
            'address' => {
              'street' => '140 Rock Creek Rd',
              'city' => 'Washington',
              'state' => 'DC',
              'country' => 'USA',
              'postalCode' => '20011'
            },
            'phone' => '3035551234',
            'emailAddress' => profile.send(:contact_information).email
          }
        )
      end
    end
  end
end
