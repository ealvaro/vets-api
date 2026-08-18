# frozen_string_literal: true

require 'rails_helper'

RSpec.describe FormProfiles::VHA107959f2 do
  subject(:profile) { described_class.new(form_id: '10-7959F-2', user:) }

  let(:user) { create(:user, :loa3) }

  describe '#metadata' do
    it 'returns prefill true when flipper enabled' do
      allow(Flipper).to receive(:enabled?).with(:form_107959f2_prefill_enabled, user).and_return(true)
      expect(profile.metadata).to eq(
        {
          version: 0,
          prefill: true,
          returnUrl: '/personal-information'
        }
      )
    end

    it 'returns prefill false when flipper disabled' do
      allow(Flipper).to receive(:enabled?).with(:form_107959f2_prefill_enabled, user).and_return(false)
      expect(profile.metadata).to eq(
        {
          version: 0,
          prefill: false,
          returnUrl: '/personal-information'
        }
      )
    end
  end

  describe '#prefill' do
    context 'when flipper enabled' do
      before do
        allow(Flipper).to receive(:enabled?).with(:form_107959f2_prefill_enabled, user).and_return(true)
      end

      it 'returns populated form_data with veteran name' do
        data = profile.prefill
        full_name = data[:form_data]['veteran']['fullName']
        expect(full_name['first']).to eq(user.first_name&.capitalize)
        expect(full_name['last']).to eq(user.last_name&.capitalize)
      end

      it 'returns populated form_data with veteran SSN' do
        data = profile.prefill
        expect(data[:form_data]['veteran']['ssn']).to eq(user.ssn_normalized)
      end

      it 'returns metadata with prefill true' do
        data = profile.prefill
        expect(data[:metadata][:prefill]).to be true
      end

      context 'with VA Profile addresses' do
        let(:contact_info) { instance_double(VAProfileRedis::V2::ContactInformation) }
        let(:mailing_address) do
          build(:va_profile_address,
                :mailing,
                :domestic,
                address_line1: '1515 Broadway',
                address_line2: 'Suite 100',
                address_line3: 'Floor 5',
                city: 'New York',
                state_code: 'NY',
                zip_code: '10036',
                country_code_iso3: 'USA')
        end
        let(:residential_address) do
          build(:va_profile_address,
                :domestic,
                address_line1: '140 Rock Creek Rd',
                address_line2: 'Apt 2',
                address_line3: 'Building B',
                city: 'Washington',
                state_code: 'DC',
                zip_code: '20011',
                country_code_iso3: 'USA')
        end
        let(:email) { instance_double(VAProfile::Models::Email, email_address: 'vet@example.com') }
        let(:home_phone) { instance_double(VAProfile::Models::Telephone, formatted_phone: '2025551234') }
        let(:mobile_phone) { instance_double(VAProfile::Models::Telephone, formatted_phone: '2025555678') }

        before do
          allow(VAProfileRedis::V2::ContactInformation).to receive(:for_user).with(user).and_return(contact_info)
          allow(contact_info).to receive_messages(
            email:,
            home_phone:,
            mobile_phone:,
            mailing_address:,
            residential_address:
          )
        end

        it 'prefills mailingAddress from VA Profile mailing address' do
          data = profile.prefill
          expect(data[:form_data]['veteran']['mailingAddress']).to eq(
            'street' => '1515 Broadway',
            'street2' => 'Suite 100',
            'street3' => 'Floor 5',
            'city' => 'New York',
            'state' => 'NY',
            'country' => 'USA',
            'postalCode' => '10036'
          )
        end

        it 'prefills residentialAddress from VA Profile residential address' do
          data = profile.prefill
          expect(data[:form_data]['veteran']['residentialAddress']).to eq(
            'street' => '140 Rock Creek Rd',
            'street2' => 'Apt 2',
            'street3' => 'Building B',
            'city' => 'Washington',
            'state' => 'DC',
            'country' => 'USA',
            'postalCode' => '20011'
          )
        end

        it 'passes home_phone, mobile_phone, us_phone, and email through from base' do
          contact = profile.send(:initialize_contact_information)
          expect(contact.home_phone).to eq('2025551234')
          expect(contact.us_phone).to eq('2025551234')
          expect(contact.mobile_phone).to eq('2025555678')
          expect(contact.email).to eq('vet@example.com')
        end

        it 'prefills veteran phoneNumber and emailAddress from VA Profile' do
          data = profile.prefill
          expect(data[:form_data]['veteran']['phoneNumber']).to eq('2025551234')
          expect(data[:form_data]['veteran']['emailAddress']).to eq('vet@example.com')
        end

        context 'when residential address is blank' do
          let(:residential_address) { nil }

          it 'omits residentialAddress from form_data' do
            data = profile.prefill
            expect(data[:form_data]['veteran']).not_to have_key('residentialAddress')
          end
        end

        context 'with overseas military addresses' do
          let(:mailing_address) do
            build(:va_profile_address,
                  :mailing,
                  :military_overseas,
                  address_line1: 'PSC 123 Box 456',
                  address_line2: nil,
                  address_line3: 'Unit 7890',
                  city: 'APO',
                  state_code: 'AE',
                  zip_code: '09012',
                  country_code_iso3: 'USA')
          end
          let(:residential_address) do
            build(:va_profile_address,
                  :military_overseas,
                  address_line1: 'CMR 456 Box 789',
                  address_line2: nil,
                  address_line3: 'Box 12',
                  city: 'FPO',
                  state_code: 'AP',
                  zip_code: '96349',
                  country_code_iso3: 'USA')
          end

          it 'prefills mailingAddress with isMilitary and street3' do
            data = profile.prefill
            expect(data[:form_data]['veteran']['mailingAddress']).to eq(
              'street' => 'PSC 123 Box 456',
              'street3' => 'Unit 7890',
              'city' => 'APO',
              'state' => 'AE',
              'country' => 'USA',
              'postalCode' => '09012',
              'isMilitary' => true
            )
          end

          it 'prefills residentialAddress with isMilitary and street3' do
            data = profile.prefill
            expect(data[:form_data]['veteran']['residentialAddress']).to eq(
              'street' => 'CMR 456 Box 789',
              'street3' => 'Box 12',
              'city' => 'FPO',
              'state' => 'AP',
              'country' => 'USA',
              'postalCode' => '96349',
              'isMilitary' => true
            )
          end
        end

        context 'with an international mailing address' do
          let(:mailing_address) do
            build(:va_profile_address,
                  :mailing,
                  :international,
                  address_line1: '10 Downing Street',
                  address_line2: nil,
                  address_line3: nil,
                  city: 'London',
                  province: 'Greater London',
                  international_postal_code: 'SW1A 2AA',
                  country_code_iso3: 'GBR',
                  zip_code: nil,
                  state_code: nil)
          end

          it 'prefills mailingAddress with the full international postal code' do
            data = profile.prefill
            expect(data[:form_data]['veteran']['mailingAddress']).to eq(
              'street' => '10 Downing Street',
              'city' => 'London',
              'state' => 'Greater London',
              'country' => 'GBR',
              'postalCode' => 'SW1A 2AA'
            )
          end
        end
      end

      context 'when VA Profile has no mailing address' do
        let(:contact_info) { instance_double(VAProfileRedis::V2::ContactInformation) }
        let(:mpi_address) do
          {
            street: '123 Main St Apt 4B',
            street2: nil,
            city: 'Springfield',
            state: 'IL',
            country: 'USA',
            postal_code: '62704-1234'
          }
        end

        before do
          allow(VAProfileRedis::V2::ContactInformation).to receive(:for_user).with(user).and_return(contact_info)
          allow(contact_info).to receive_messages(
            email: nil,
            home_phone: nil,
            mobile_phone: nil,
            mailing_address: nil,
            residential_address: nil
          )
          allow(user).to receive(:address).and_return(mpi_address)
        end

        it 'prefills mailingAddress from the MPI fallback address' do
          data = profile.prefill
          expect(data[:form_data]['veteran']['mailingAddress']).to eq(
            'street' => '123 Main St',
            'street2' => 'Apt 4B',
            'city' => 'Springfield',
            'state' => 'IL',
            'country' => 'USA',
            'postalCode' => '62704'
          )
        end

        it 'omits residentialAddress when VA Profile has none' do
          data = profile.prefill
          expect(data[:form_data]['veteran']).not_to have_key('residentialAddress')
        end
      end
    end

    context 'when flipper disabled' do
      before do
        allow(Flipper).to receive(:enabled?).with(:form_107959f2_prefill_enabled, user).and_return(false)
      end

      it 'returns empty form_data' do
        data = profile.prefill
        expect(data[:form_data]).to eq({})
      end

      it 'returns metadata with prefill false' do
        data = profile.prefill
        expect(data[:metadata][:prefill]).to be false
      end
    end
  end
end
