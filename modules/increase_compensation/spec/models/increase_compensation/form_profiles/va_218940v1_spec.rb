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
      allow(Flipper).to receive(:enabled?).with(:form_218940_disability_prefill_enabled).and_return(false)

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

    context 'when the rated disabilities fetch fails' do
      it 'sets ratedDisabilitiesFetchFailed to true in form_data' do
        new_subject = described_class.new(form_id:, user:)
        allow(user).to receive(:authorize).and_return(true)
        allow(Flipper).to receive(:enabled?).with(:form_218940_prefill_enabled).and_return(true)
        allow(Flipper).to receive(:enabled?).with(:form_218940_disability_prefill_enabled).and_return(true)
        allow(new_subject).to receive(:initialize_rated_disabilities_information) do
          new_subject.instance_variable_set(:@rated_disabilities_fetch_failed, true)
          IncreaseCompensation::FormProfiles::VA218940v1::DisabilityList.new(rated_disabilities: [])
        end

        result = new_subject.prefill

        expect(result[:form_data]['ratedDisabilitiesFetchFailed']).to be(true)
      end
    end

    context 'when the rated disabilities fetch succeeds' do
      it 'does not set ratedDisabilitiesFetchFailed in form_data' do
        new_subject = described_class.new(form_id:, user:)
        allow(user).to receive(:authorize).and_return(true)
        allow(Flipper).to receive(:enabled?).with(:form_218940_prefill_enabled).and_return(true)
        allow(Flipper).to receive(:enabled?).with(:form_218940_disability_prefill_enabled).and_return(true)
        allow(new_subject).to receive(:initialize_rated_disabilities_information).and_return(disability_list)

        result = new_subject.prefill

        expect(result[:form_data]).not_to have_key('ratedDisabilitiesFetchFailed')
      end
    end

    context 'when form_data is nil (form_id not in prefill_enabled_forms)' do
      it 'does not attempt to set the flag and does not raise' do
        allow(FormProfile).to receive(:prefill_enabled_forms).and_return([])
        allow(user).to receive(:authorize).and_return(true)
        allow(Flipper).to receive(:enabled?).with(:form_218940_prefill_enabled).and_return(true)
        new_subject = described_class.new(form_id:, user:)
        new_subject.instance_variable_set(:@rated_disabilities_fetch_failed, true)

        result = nil
        expect { result = new_subject.prefill }.not_to raise_error
        expect(result[:form_data]).to be_nil
      end
    end
  end

  describe '#initialize_rated_disabilities_information' do
    let(:api_provider) { instance_double(LighthouseRatedDisabilitiesProvider) }

    before do
      allow(user).to receive(:authorize).with(:evss, :access?).and_return(true)
      allow(user).to receive(:authorize).with(:lighthouse, :access_vet_status?).and_return(true)
      allow(ApiProviderFactory).to receive(:call).and_return(api_provider)
    end

    context 'when the Lighthouse call raises' do
      before do
        allow(api_provider).to receive(:get_rated_disabilities).and_raise(Common::Exceptions::ServiceUnavailable)
      end

      it 'returns an empty DisabilityList rather than a bare hash' do
        result = subject.send(:initialize_rated_disabilities_information)

        expect(result).to be_a(IncreaseCompensation::FormProfiles::VA218940v1::DisabilityList)
        expect(result.rated_disabilities).to eq([])
      end

      it 'sets @rated_disabilities_fetch_failed to true' do
        subject.send(:initialize_rated_disabilities_information)

        expect(subject.instance_variable_get(:@rated_disabilities_fetch_failed)).to be(true)
      end

      it 'logs the error' do
        expect(Rails.logger).to receive(:error).with(
          'IncreaseCompensation::FormProfile Fetch Disabilities Error',
          hash_including(:error)
        )

        subject.send(:initialize_rated_disabilities_information)
      end
    end

    context 'when the Lighthouse call succeeds' do
      before do
        allow(api_provider).to receive(:get_rated_disabilities).and_return(
          instance_double(DisabilityCompensation::ApiProvider::RatedDisabilitiesResponse,
                          rated_disabilities: rated_response.map { |r| double('rated_disability', **r) })
        )
      end

      it 'does not set @rated_disabilities_fetch_failed' do
        subject.send(:initialize_rated_disabilities_information)

        expect(subject.instance_variable_get(:@rated_disabilities_fetch_failed)).to be_nil
      end
    end
  end
end
