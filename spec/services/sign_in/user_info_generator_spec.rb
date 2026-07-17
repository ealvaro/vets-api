# frozen_string_literal: true

require 'rails_helper'

RSpec.describe SignIn::UserInfoGenerator do
  subject(:generator) { described_class.new(user:) }

  let(:user_account) { create(:user_account, icn:) }
  let(:user_verification) { create(:idme_user_verification, idme_uuid: credential_uuid, user_account:) }

  let(:mpi_profile) do
    build(:mpi_profile, icn:, sec_id:, sec_id_history:, given_names: [first_name], family_name: last_name, edipi:,
                        mhv_ien:, cerner_id:, participant_id: corp_id, birls_id: birls, full_mvi_ids: gcids)
  end
  let(:user) do
    build(
      :user,
      user_account:,
      user_verification:,
      icn:,
      idme_uuid: credential_uuid,
      first_name:,
      middle_name:,
      last_name:
    )
  end
  let(:credential_uuid) { 'some-uuid' }
  let(:icn) { 'some-icn' }
  let(:sec_id) { 'some-sec-id' }
  let(:sec_id_history) { %w[hist-sec-id-1 hist-sec-id-2] }
  let(:first_name) { 'some-first-name' }
  let(:middle_name) { 'some-middle-name' }
  let(:last_name) { 'some-last-name' }
  let(:email) { 'some-email' }
  let(:client_id) { 'some-client-id' }
  let(:edipi) { 'some-edipi' }
  let(:mhv_ien) { '111222333' }
  let(:cerner_id) { 'CER12345' }
  let(:corp_id) { 'CORP67890' }
  let(:birls) { 'BIRL12345' }
  let(:gcids) do
    [
      '1000123456V123456^NI^200M^USVHA^P',
      '12345^PI^516^USVHA^PCE',
      '2^PI^553^USVHA^PCE',
      '16015218^PI^742V1^USVHA^A'
    ]
  end
  let(:npi_id) { 'NPI1234567' }

  let!(:user_credential_email) { create(:user_credential_email, user_verification:, credential_email:) }
  let(:credential_email) { 'test@example.com' }

  before do
    allow(user).to receive(:mpi_profile).and_return(mpi_profile)
  end

  describe '#perform' do
    context 'when user has valid attributes' do
      it 'generates user info with expected values' do
        user_info = generator.perform

        expect(user_info.sub).to eq(credential_uuid)
        expect(user_info.ial).to eq(SignIn::Constants::Auth::IAL_TWO.to_s)
        expect(user_info.aal).to eq('http://idmanagement.gov/ns/assurance/aal/2')
        expect(user_info.csp_type).to eq(MPI::Constants::IDME_IDENTIFIER)
        expect(user_info.csp_uuid).to eq(credential_uuid)
        expect(user_info.email).to eq(credential_email)
        expect(user_info.first_name).to eq(user.first_name)
        expect(user_info.middle_name).to eq(user.middle_name)
        expect(user_info.last_name).to eq(user.last_name)
        expect(user_info.full_name).to eq(user.full_name_normalized.values.compact.join(' '))
        expect(user_info.birth_date).to eq(user.birth_date)
        expect(user_info.ssn).to eq(user.ssn)
        expect(user_info.gender).to eq(user.gender)
        expect(user_info.address_street1).to eq(user.address[:street])
        expect(user_info.address_street2).to eq(user.address[:street2])
        expect(user_info.address_city).to eq(user.address[:city])
        expect(user_info.address_state).to eq(user.address[:state])
        expect(user_info.address_country).to eq(user.address[:country])
        expect(user_info.address_postal_code).to eq(user.address[:postal_code])
        expect(user_info.phone_number).to eq(user.home_phone)
        expect(user_info.person_types).to eq(user.person_types&.join('|') || '')
        expect(user_info.icn).to eq(user.icn)
        expect(user_info.sec_id).to eq(user.sec_id)
        expect(user_info.sec_id_history).to eq(user.sec_id_history.join('^'))
        expect(user_info.edipi).to eq(user.edipi)
        expect(user_info.mhv_ien).to eq(user.mhv_ien)
        expect(user_info.cerner_id).to eq(user.cerner_id)
        expect(user_info.corp_id).to eq(user.participant_id)
        expect(user_info.birls).to eq(user.birls_id)
        expect(user_info.npi_id).to eq(user.npi_id)
      end

      context 'when user already has a valid address' do
        let(:user_address) do
          {
            street: '123 Main St',
            street2: 'Apt 1',
            city: 'Dallas',
            state: 'TX',
            country: 'USA',
            postal_code: '75001'
          }
        end

        before do
          allow(user).to receive(:address).and_return(user_address)
        end

        it 'does not call MPI and uses user address' do
          expect_any_instance_of(MPI::Service)
            .not_to receive(:find_profile_by_identifier)

          user_info = generator.perform

          expect(user_info.address_street1).to eq(user_address[:street])
          expect(user_info.address_street2).to eq(user_address[:street2])
          expect(user_info.address_city).to eq(user_address[:city])
          expect(user_info.address_state).to eq(user_address[:state])
          expect(user_info.address_country).to eq(user_address[:country])
          expect(user_info.address_postal_code).to eq(user_address[:postal_code])
        end
      end

      context 'when user address is blank and fallback is MPI' do
        let(:user_address) { {} }
        let(:mpi_address) do
          {
            street: '456 Main St',
            street2: 'Unit 9',
            city: 'Austin',
            state: 'TX',
            country: 'USA',
            postal_code: '75001'
          }
        end

        let(:mpi_profile) { build(:mpi_profile, address: mpi_address) }
        let(:status) { MPI::Responses::FindProfileResponse::OK }
        let(:find_profile_response) { build(:find_profile_response, profile: mpi_profile, status:) }

        before do
          allow(user).to receive(:address).and_return(user_address)
          allow_any_instance_of(MPI::Service)
            .to receive(:find_profile_by_identifier)
            .and_return(find_profile_response)
        end

        context 'when MPI response is ok' do
          it 'returns the MPI address' do
            user_info = generator.perform

            expect(user_info.address_street1).to eq(mpi_address[:street])
            expect(user_info.address_street2).to eq(mpi_address[:street2])
            expect(user_info.address_city).to eq(mpi_address[:city])
            expect(user_info.address_state).to eq(mpi_address[:state])
            expect(user_info.address_country).to eq(mpi_address[:country])
            expect(user_info.address_postal_code).to eq(mpi_address[:postal_code])
          end

          it 'calls MPI with correct parameters' do
            expect_any_instance_of(MPI::Service)
              .to receive(:find_profile_by_identifier)
              .with(
                identifier: credential_uuid,
                identifier_type: user_verification.credential_type,
                view_type: MPI::Constants::CORRELATION_VIEW
              )

            generator.perform
          end
        end

        context 'when MPI response is not ok' do
          let(:status) { MPI::Responses::FindProfileResponse::SERVER_ERROR }

          it 'returns empty address' do
            user_info = generator.perform

            expect(user_info.address_street1).to be_nil
            expect(user_info.address_street2).to be_nil
            expect(user_info.address_city).to be_nil
            expect(user_info.address_state).to be_nil
            expect(user_info.address_country).to be_nil
            expect(user_info.address_postal_code).to be_nil
          end
        end

        context 'when MPI correlation profile has no address' do
          let(:mpi_profile) { build(:mpi_profile, address: {}) }

          it 'returns empty address' do
            user_info = generator.perform

            expect(user_info.address_street1).to be_nil
            expect(user_info.address_street2).to be_nil
            expect(user_info.address_city).to be_nil
            expect(user_info.address_state).to be_nil
            expect(user_info.address_country).to be_nil
            expect(user_info.address_postal_code).to be_nil
          end
        end

        context 'when MPI correlation profile address is nil' do
          let(:mpi_profile) { build(:mpi_profile, address: nil) }

          it 'returns empty address without raising an error' do
            user_info = nil

            expect { user_info = generator.perform }.not_to raise_error

            expect(user_info.address_street1).to be_nil
            expect(user_info.address_street2).to be_nil
            expect(user_info.address_city).to be_nil
            expect(user_info.address_state).to be_nil
            expect(user_info.address_country).to be_nil
            expect(user_info.address_postal_code).to be_nil
          end
        end
      end

      context 'when user phone number is blank and fallback is MPI' do
        let(:user_phone_number) {}
        let(:mpi_home_phone) { '123-456-789' }

        let(:mpi_profile) { build(:mpi_profile, home_phone: mpi_home_phone) }
        let(:status) { MPI::Responses::FindProfileResponse::OK }
        let(:find_profile_response) { build(:find_profile_response, profile: mpi_profile, status:) }

        before do
          allow(user).to receive(:home_phone).and_return(user_phone_number)
          allow_any_instance_of(MPI::Service)
            .to receive(:find_profile_by_identifier)
            .and_return(find_profile_response)
        end

        context 'when MPI response is ok' do
          it 'returns the MPI phone number' do
            user_info = generator.perform

            expect(user_info.phone_number).to eq(mpi_home_phone)
          end

          it 'calls MPI with correct parameters' do
            expect_any_instance_of(MPI::Service)
              .to receive(:find_profile_by_identifier)
              .with(
                identifier: credential_uuid,
                identifier_type: user_verification.credential_type,
                view_type: MPI::Constants::CORRELATION_VIEW
              )

            generator.perform
          end
        end

        context 'when MPI response is not ok' do
          let(:status) { MPI::Responses::FindProfileResponse::SERVER_ERROR }

          it 'returns empty phone number' do
            user_info = generator.perform
            expect(user_info.phone_number).to be_nil
          end
        end

        context 'when MPI correlation profile has no phone number' do
          let(:mpi_profile) { build(:mpi_profile, home_phone: nil) }

          it 'returns empty phone number' do
            user_info = generator.perform

            expect(user_info.phone_number).to be_nil
          end
        end

        context 'when MPI correlation profile phone number is nil' do
          let(:mpi_profile) { build(:mpi_profile, address: nil) }

          it 'returns empty phone number without raising an error' do
            user_info = nil

            expect { user_info = generator.perform }.not_to raise_error

            expect(user_info.address_street1).to be_nil
            expect(user_info.address_street2).to be_nil
            expect(user_info.address_city).to be_nil
            expect(user_info.address_state).to be_nil
            expect(user_info.address_country).to be_nil
            expect(user_info.address_postal_code).to be_nil
          end
        end
      end

      context 'when the gcids are valid' do
        let(:expected_gcids) do
          '1000123456V123456^NI^200M^USVHA^P|12345^PI^516^USVHA^PCE|2^PI^553^USVHA^PCE|16015218^PI^742V1^USVHA^A'
        end

        it 'includes them in the user info' do
          user_info = generator.perform
          expect(user_info.gcids).to eq(expected_gcids)
        end
      end

      context 'when the gcids are not authorized' do
        let(:gcids) do
          [
            '1000123456V123456^NI^200BAD^USVHA^P',
            '1000123456V123456^NI^200INVALID^USVHA^P',
            '12345^PI^200VHIC^USVHA^P'
          ]
        end

        it 'excludes them from the user info' do
          user_info = generator.perform
          expect(user_info.gcids).to eq('')
        end
      end
    end
  end
end
