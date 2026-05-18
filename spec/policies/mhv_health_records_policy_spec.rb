# frozen_string_literal: true

require 'rails_helper'
require 'mhv_health_records_policy'

describe MHVHealthRecordsPolicy do
  let(:mhv_health_records) { double('mhv_health_records') }

  describe '#access?' do
    subject { described_class.new(user, mhv_health_records).access? }

    context 'when user is not LOA3' do
      let(:user) { create(:user, :loa1) }

      it 'returns false' do
        expect(subject).to be(false)
      end
    end

    context 'when user is LOA3' do
      let(:user) { create(:user, :loa3, :with_terms_of_use_agreement, mhv_account_creation: { patient: true }) }

      context 'and mhv_user_account is present' do
        it 'returns true' do
          expect(subject).to be(true)
        end
      end

      context 'and mhv_user_account is nil' do
        let(:user) { create(:user, :loa3, mhv_user_account: nil) }

        it 'returns false' do
          expect(subject).to be(false)
        end
      end
    end
  end
end
