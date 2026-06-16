# frozen_string_literal: true

require 'rails_helper'

RSpec.describe FormProfiles::VA10297 do
  subject(:profile) { described_class.new(form_id: '22-10297', user:) }

  let(:user) { create(:user, icn: '123498767V234859') }

  describe '#metadata' do
    it 'returns expected metadata' do
      expect(profile.metadata).to eq({ version: 0, prefill: true, returnUrl: '/applicant/information' })
    end
  end

  describe '#prefill' do
    before do
      allow(user).to receive(:authorize).with(:evss, :access?).and_return(true)
      allow(user).to receive(:authorize).with(:va_profile, :access_to_v2?).and_return(true)
      allow(user).to receive(:authorize).with(:lighthouse, :direct_deposit_access?).and_return(true)
      allow_any_instance_of(Auth::ClientCredentials::Service).to receive(:get_token).and_return('fake_token')
    end

    it 'prefills form data' do
      VCR.use_cassette('lighthouse/direct_deposit/show/200_valid_new_icn') do
        data = profile.prefill
        expect(data[:form_data]['mailingAddress']).to eq({ 'street' => '140 Rock Creek Rd',
                                                           'city' => 'Washington',
                                                           'state' => 'DC',
                                                           'country' => 'USA',
                                                           'postalCode' => '20011' })
        expect(data[:form_data]['bankAccount']).to eq({ 'bankAccountType' => 'Checking',
                                                        'bankAccountNumber' => '1234567890',
                                                        'bankRoutingNumber' => '031000503',
                                                        'bankName' => 'WELLS FARGO BANK' })
      end
    end

    it 'strips suffix from applicantFullName when present' do
      VCR.use_cassette('lighthouse/direct_deposit/show/200_valid_new_icn') do
        data = profile.prefill
        expect(data[:form_data].fetch('applicantFullName', {})).not_to have_key('suffix')
      end
    end

    context 'when applicantFullName is absent from prefill data' do
      let(:nameless_profile) { described_class.new(form_id: '22-10297', user:) }

      before do
        allow(nameless_profile).to receive_messages(
          initialize_payment_information: {},
          initialize_identity_information: FormIdentityInformation.new(full_name: nil, date_of_birth: nil,
                                                                       gender: nil, ssn: nil),
          initialize_contact_information: FormContactInformation.new,
          initialize_military_information: FormMilitaryInformation.new
        )
      end

      it 'does not raise NoMethodError' do
        expect { nameless_profile.prefill }.not_to raise_error
      end
    end
  end
end
