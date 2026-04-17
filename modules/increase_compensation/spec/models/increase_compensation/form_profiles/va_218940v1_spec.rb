# frozen_string_literal: true

require 'rails_helper'

RSpec.describe IncreaseCompensation::FormProfiles::VA218940v1, type: :model do
  subject { described_class.new(form_id:, user:) }

  let(:user) { build(:user, :loa3) }
  let(:form_id) { '21-8940v1' }
  let(:address) { instance_double(Address, country: 'USA') }
  let(:disability_list) do
    double('disability_list',
           { rated_disabilities: [{ 'disability' => 'bilateral hearing loss' }] })
  end

  let(:rated_response) do
    [
      {
        name: 'bilateral hearing loss',
        decision_code: 'SVCCONNCTED',
        decision_text: 'Service Connected',
        diagnostic_code: '0502',
        effective_date: '2018-03-27',
        rated_disability_id: '1070379',
        rating_decision_id: 0,
        rating_percentage: 50
      }
    ]
  end

  before do
    allow(FormProfile).to receive(:prefill_enabled_forms).and_return([form_id])
  end

  describe '#metadata' do
    it 'returns correct metadata' do
      allow(Flipper).to receive(:enabled?).with(:form_218940_prefill_enabled).and_return(true)
      expect(subject.metadata).to eq(
        version: 0,
        prefill: true,
        returnUrl: '/confirmation-question'
      )

      subject.metadata
    end

    it 'returns correct metadata when disabled' do
      allow(Flipper).to receive(:enabled?).with(:form_218940_prefill_enabled).and_return(false)
      expect(subject.metadata).to eq(
        version: 0,
        prefill: false,
        returnUrl: '/confirmation-question'
      )

      subject.metadata
    end
  end

  describe '#prefill' do
    it 'initializes identity and contact information' do
      allow(Flipper).to receive(:enabled?).with(:form_218940_prefill_enabled).and_return(true)
      expect(subject.prefill).to match(
        {
          form_data: {
            'veteranFullName' => {
              'first' => 'Abraham',
              'last' => 'Lincoln',
              'suffix' => 'Jr.'
            },
            'veteranSocialSecurityNumber' => '796111863',
            'veteranAddress' => { 'street' => '140 Rock Creek Rd',
                                  'city' => 'Washington',
                                  'state' => 'DC',
                                  'country' => 'USA',
                                  'postalCode' => '20011' }, 'veteranPhone' => '3035551234',
            'email' => user.va_profile_email,
            'emailAddress' => user.va_profile_email,
            'veteranDateOfBirth' => '1809-02-12'
          },
          metadata: {
            version: 0,
            prefill: true,
            returnUrl: '/confirmation-question'
          }
        }
      )
    end

    it 'Finds disability data to prefill' do
      new_subject = described_class.new(form_id:, user:)
      allow(Flipper).to receive(:enabled?).with(:form_218940_prefill_enabled).and_return(true)
      allow(Flipper).to receive(:enabled?).with(:form_218940_disability_prefill_enabled).and_return(true)
      allow(new_subject).to receive(:initialize_rated_disabilities_information)
        .and_return(disability_list)

      expect(new_subject.prefill).to match(
        {
          form_data: {
            'veteranFullName' => {
              'first' => 'Abraham',
              'last' => 'Lincoln',
              'suffix' => 'Jr.'
            },
            'veteranSocialSecurityNumber' => '796111863',
            'veteranAddress' => { 'street' => '140 Rock Creek Rd',
                                  'city' => 'Washington',
                                  'state' => 'DC',
                                  'country' => 'USA',
                                  'postalCode' => '20011' }, 'veteranPhone' => '3035551234',
            'email' => user.va_profile_email,
            'emailAddress' => user.va_profile_email,
            'veteranDateOfBirth' => '1809-02-12',
            'disabilityDescription' => [
              {
                'disability' => 'bilateral hearing loss'
              }
            ]
          },
          metadata: {
            version: 0,
            prefill: true,
            returnUrl: '/confirmation-question'
          }
        }
      )
    end
  end
end
