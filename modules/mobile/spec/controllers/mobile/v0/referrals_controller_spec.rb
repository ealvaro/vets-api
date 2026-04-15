# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Mobile::V0::ReferralsController, type: :controller do
  let(:controller) { described_class.new }

  describe '#filter_by_category_of_care' do
    let(:primary_care_referral) { build(:ccra_referral_list_entry, category_of_care: 'primary care') }
    let(:cardiology_referral) { build(:ccra_referral_list_entry, category_of_care: 'cardiology') }
    let(:nil_category_referral) { build(:ccra_referral_list_entry, category_of_care: nil) }

    it 'keeps primary care referrals' do
      result = controller.send(:filter_by_category_of_care, [primary_care_referral, cardiology_referral])
      expect(result).to contain_exactly(primary_care_referral)
    end

    it 'filters out unsupported categories' do
      result = controller.send(:filter_by_category_of_care, [cardiology_referral])
      expect(result).to be_empty
    end

    it 'filters out referrals with nil category_of_care' do
      result = controller.send(:filter_by_category_of_care, [nil_category_referral])
      expect(result).to be_empty
    end

    it 'is case insensitive' do
      upcased = build(:ccra_referral_list_entry, category_of_care: 'PRIMARY CARE')
      result = controller.send(:filter_by_category_of_care, [upcased])
      expect(result).to contain_exactly(upcased)
    end
  end

  describe '#filter_expired_referrals' do
    let(:active_referral) { build(:ccra_referral_list_entry, referral_expiration_date: (Date.current + 30.days).to_s) }
    let(:expired_referral) { build(:ccra_referral_list_entry, referral_expiration_date: (Date.current - 1.day).to_s) }
    let(:no_expiration_referral) { build(:ccra_referral_list_entry, referral_expiration_date: nil) }

    it 'returns an empty array when referrals is nil' do
      expect(controller.send(:filter_expired_referrals, nil)).to eq([])
    end

    it 'raises an error when referrals is not enumerable' do
      expect { controller.send(:filter_expired_referrals, 'not_a_collection') }
        .to raise_error(ArgumentError, 'referrals must be an enumerable collection')
    end

    it 'filters out expired referrals' do
      result = controller.send(:filter_expired_referrals, [active_referral, expired_referral])
      expect(result).to contain_exactly(active_referral)
    end

    it 'keeps referrals with no expiration date' do
      result = controller.send(:filter_expired_referrals, [active_referral, no_expiration_referral])
      expect(result).to contain_exactly(active_referral, no_expiration_referral)
    end

    it 'returns all referrals when none are expired' do
      result = controller.send(:filter_expired_referrals, [active_referral, no_expiration_referral])
      expect(result.length).to eq(2)
    end
  end

  describe '#add_referral_uuids' do
    let(:referrals) { build_list(:ccra_referral_list_entry, 2) }

    before do
      referrals.each do |referral|
        allow(VAOS::ReferralEncryptionService).to receive(:encrypt)
          .with(referral.referral_consult_id)
          .and_return("encrypted-#{referral.referral_consult_id}")
      end
    end

    it 'sets an encrypted uuid on each referral' do
      controller.send(:add_referral_uuids, referrals)

      referrals.each do |referral|
        expect(referral.uuid).to eq("encrypted-#{referral.referral_consult_id}")
      end
    end

    it 'returns the referrals unchanged when not enumerable' do
      result = controller.send(:add_referral_uuids, 'not_a_collection')
      expect(result).to eq('not_a_collection')
    end
  end

  describe '#referral_status_param' do
    it "defaults to \"'AP', 'C'\" when no status param is provided" do
      allow(controller).to receive(:params).and_return(ActionController::Parameters.new({}))
      expect(controller.send(:referral_status_param)).to eq("'AP', 'C'")
    end

    it 'returns the provided status param' do
      allow(controller).to receive(:params).and_return(ActionController::Parameters.new({ status: "'AP'" }))
      expect(controller.send(:referral_status_param)).to eq("'AP'")
    end
  end
end
