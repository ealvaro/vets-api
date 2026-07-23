# frozen_string_literal: true

require 'rails_helper'

RSpec.describe SurvivorsBenefits::FormProfiles::VA21p534ez do
  subject(:profile) { described_class.new(form_id: '21P-534EZ', user:) }

  let(:user) { create(:user, icn: '123498767V234859') }

  describe '#metadata' do
    it 'returns expected metadata' do
      expect(profile.metadata).to eq({ version: 0, prefill: true, returnUrl: '/claimant-relationship' })
    end
  end

  describe '#prefill' do
    let(:vet360_contact_info) { nil }

    before do
      allow(FormProfile).to receive(:prefill_enabled_forms).and_return(['21P-534EZ'])
      allow(VAProfileRedis::V2::ContactInformation).to receive(:for_user).with(user).and_return(vet360_contact_info)
      allow(user).to receive_messages(
        email: 'abraham.lincoln@vets.gov',
        home_phone: '(800) 867-5309'
      )
    end

    context 'when contact information has phone and email' do
      let(:vet360_contact_info) do
        double(
          'contact_information',
          email: double('email', email_address: 'from.contact.info@va.gov'),
          home_phone: double('phone', formatted_phone: '3035551234'),
          mobile_phone: nil,
          mailing_address: nil
        )
      end

      it 'uses contact information values in prefill form data' do
        data = profile.prefill

        expect(data[:form_data]['yourPhone']).to eq({ 'contact' => '3035551234' })
        expect(data[:form_data]['yourEmail']).to eq('from.contact.info@va.gov')
      end
    end

    context 'when contact information phone and email are nil' do
      it 'falls back to user phone and email in prefill form data' do
        data = profile.prefill

        expect(data[:form_data]['yourPhone']).to eq({ 'contact' => '8008675309' })
        expect(data[:form_data]['yourEmail']).to eq('abraham.lincoln@vets.gov')
        expect(data[:metadata]).to eq({ version: 0, prefill: true, returnUrl: '/claimant-relationship' })
      end
    end
  end

  describe '#va_file_number' do
    let(:request) { instance_double(BGS::People::Request) }

    before do
      allow(BGS::People::Request).to receive(:new).and_return(request)
    end

    it 'returns the BGS file number when present' do
      allow(request).to receive(:find_person_by_participant_id).with(user:).and_return(
        instance_double(BGS::People::Response, file_number: '796043735')
      )

      expect(profile.va_file_number).to eq('796043735')
    end

    it 'falls back to the user ssn when BGS file number is blank' do
      allow(request).to receive(:find_person_by_participant_id).with(user:).and_return(
        instance_double(BGS::People::Response, file_number: nil)
      )

      expect(profile.va_file_number).to eq('796111863')
    end
  end
end
