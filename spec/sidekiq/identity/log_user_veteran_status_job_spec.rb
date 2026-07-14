# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Identity::LogUserVeteranStatusJob do
  subject { described_class.new.perform(user_uuid) }

  let(:user) { create(:user, :loa3) }
  let(:user_uuid) { user.uuid }

  before do
    allow(User).to receive(:find).with(user_uuid).and_return(user)
    allow(Rails.logger).to receive(:info)
  end

  context 'when the user is loa3, has an EDIPI, and VA Profile returns veteran status' do
    it 'logs veteran status with is_veteran = true' do
      VCR.use_cassette('va_profile/veteran_status/va_profile_veteran_status_200', match_requests_on: [:method]) do
        subject

        expect(Rails.logger).to have_received(:info).with(
          'user_veteran_status',
          {
            icn: user.icn,
            user_uuid: user.uuid,
            is_veteran: true,
            safe_keys: [:icn]
          }
        )
      end
    end
  end

  context 'when the VA Profile returns a 404 error' do
    it 'logs veteran status with is_veteran = false' do
      VCR.use_cassette('va_profile/veteran_status/veteran_status_404_oid_blank', match_requests_on: [:method]) do
        expect { subject }.not_to raise_error
        expect(Rails.logger).to have_received(:info).with(
          'user_veteran_status',
          {
            icn: user.icn,
            user_uuid: user.uuid,
            is_veteran: false,
            safe_keys: [:icn]
          }
        )
      end
    end
  end

  context 'for unverified users' do
    let(:user) { create(:user, :loa1, icn: nil) }

    before { allow(user).to receive(:veteran?) }

    it 'logs non-veteran status without querying VA Profile' do
      subject

      expect(user).not_to have_received(:veteran?)
      expect(Rails.logger).to have_received(:info).with(
        'user_veteran_status',
        {
          icn: nil,
          user_uuid: user.uuid,
          is_veteran: false,
          safe_keys: [:icn]
        }
      )
    end
  end

  context 'for users without an EDIPI' do
    let(:user) { create(:user, edipi: nil) }

    before { allow(user).to receive(:veteran?) }

    it 'logs non-veteran status without querying VA Profile' do
      subject

      expect(user).not_to have_received(:veteran?)
      expect(Rails.logger).to have_received(:info).with(
        'user_veteran_status',
        {
          icn: user.icn,
          user_uuid: user.uuid,
          is_veteran: false,
          safe_keys: [:icn]
        }
      )
    end
  end

  context 'when the User object is not found in Redis' do
    let(:user_uuid) { 'some-user_uuid' }
    let(:user) { nil }

    it 'exits without raising an error' do
      expect { subject }.not_to raise_error
    end

    it 'does not create a veteran_status log' do
      subject

      expect(Rails.logger).not_to have_received(:info)
    end
  end
end
