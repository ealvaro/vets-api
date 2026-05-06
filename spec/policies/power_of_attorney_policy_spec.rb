# frozen_string_literal: true

require 'rails_helper'

describe PowerOfAttorneyPolicy do
  subject { described_class }

  permissions :access? do
    context 'when user is LOA3 and has an ICN' do
      let(:user) { build(:user, :loa3) }

      it 'grants access and does not log' do
        expect(Rails.logger).not_to receive(:info).with('POA ACCESS DENIED', anything)
        expect(subject).to permit(user, :power_of_attorney)
      end
    end

    context 'when user is LOA3 but does not have an ICN' do
      let(:user) { build(:user, :loa3, icn: nil) }

      it 'denies access due to missing ICN and logs the access denial details' do
        expect(Rails.logger).to receive(:info).with(
          'POA ACCESS DENIED',
          hash_including(
            loa_current: 3,
            loa3: true,
            icn_present: false
          )
        )
        expect(subject).not_to permit(user, :power_of_attorney)
      end
    end

    context 'when user is not LOA3' do
      let(:user) { build(:user, :loa1) }

      it 'denies access due to not being LOA3 and logs the access denial details' do
        expect(Rails.logger).to receive(:info).with(
          'POA ACCESS DENIED',
          hash_including(
            loa_current: 1,
            loa3: false,
            icn_present: true
          )
        )
        expect(subject).not_to permit(user, :power_of_attorney)
      end
    end
  end
end
