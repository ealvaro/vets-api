# frozen_string_literal: true

require 'rails_helper'
require 'benefits_claims/providers/ivc_champva/ivc_champva_benefits_claims_provider'
require 'support/benefits_claims/benefits_claims_provider'

RSpec.describe BenefitsClaims::Providers::IvcChampva::IvcChampvaBenefitsClaimsProvider do
  subject(:provider) { described_class.new(current_user) }

  let(:current_user) { build(:user, email: 'primary@example.com') }

  it_behaves_like 'benefits claims provider'

  describe '#get_claims' do
    context 'when the user has no emails' do
      let(:current_user) { nil }

      it 'returns an empty response' do
        expect(provider.get_claims).to eq('data' => [])
      end
    end

    it 'queries by normalized user email and credential email, grouped by form_uuid' do
      current_user.user_account.user_verifications.first.user_credential_email.update!(
        credential_email: 'secondary@example.com'
      )

      uuid_one = SecureRandom.uuid
      uuid_two = SecureRandom.uuid

      oldest = create(:ivc_champva_form, form_uuid: uuid_one, email: '  PRIMARY@example.com  ', created_at: 2.days.ago)
      newest_same_uuid = create(
        :ivc_champva_form, form_uuid: uuid_one, email: 'primary@example.com', created_at: 1.day.ago
      )
      second_claim = create(
        :ivc_champva_form, form_uuid: uuid_two, email: 'secondary@example.com', created_at: Time.zone.now
      )
      create(:ivc_champva_form, form_uuid: SecureRandom.uuid, email: 'other@example.com')

      dto_one = instance_double(BenefitsClaims::Responses::ClaimResponse)
      dto_two = instance_double(BenefitsClaims::Responses::ClaimResponse)

      expect(BenefitsClaims::Providers::IvcChampva::ClaimBuilder).to receive(:build_claim_response)
        .with([oldest, newest_same_uuid], current_user).ordered.and_return(dto_one)
      expect(BenefitsClaims::Providers::IvcChampva::ClaimSerializer).to receive(:to_json_api)
        .with(dto_one).ordered.and_return('id' => uuid_one)

      expect(BenefitsClaims::Providers::IvcChampva::ClaimBuilder).to receive(:build_claim_response)
        .with([second_claim], current_user).ordered.and_return(dto_two)
      expect(BenefitsClaims::Providers::IvcChampva::ClaimSerializer).to receive(:to_json_api)
        .with(dto_two).ordered.and_return('id' => uuid_two)

      expect(provider.get_claims).to eq('data' => [{ 'id' => uuid_one }, { 'id' => uuid_two }])
    end
  end

  describe '#get_claim' do
    let(:claim_id) { SecureRandom.uuid }

    context 'when the user has no emails' do
      let(:current_user) { nil }

      it 'raises record not found' do
        expect { provider.get_claim(claim_id) }.to raise_error(Common::Exceptions::RecordNotFound)
      end
    end

    it 'raises record not found when no matching claim exists' do
      create(:ivc_champva_form, form_uuid: SecureRandom.uuid, email: 'other@example.com')

      expect { provider.get_claim(claim_id) }.to raise_error(Common::Exceptions::RecordNotFound)
    end

    it 'returns a single transformed claim for the requested id' do
      older = create(:ivc_champva_form, form_uuid: claim_id, email: 'primary@example.com', created_at: 2.days.ago)
      newer = create(:ivc_champva_form, form_uuid: claim_id, email: 'primary@example.com', created_at: 1.day.ago)

      dto = instance_double(BenefitsClaims::Responses::ClaimResponse)
      expect(BenefitsClaims::Providers::IvcChampva::ClaimBuilder).to receive(:build_claim_response)
        .with([older, newer], current_user).and_return(dto)
      expect(BenefitsClaims::Providers::IvcChampva::ClaimSerializer).to receive(:to_json_api)
        .with(dto).and_return('id' => claim_id)

      expect(provider.get_claim(claim_id)).to eq('data' => { 'id' => claim_id })
    end

    it 'includes ivc_champva as provider in serialized attributes' do
      create(:ivc_champva_form, form_uuid: claim_id, email: 'primary@example.com', created_at: 1.day.ago)

      result = provider.get_claim(claim_id)
      expect(result.dig('data', 'attributes', 'provider')).to eq('ivc_champva')
    end

    context 'when the claim has a Processed pega_status' do
      it 'sets decisionLetterSent to true in serialized attributes' do
        create(:ivc_champva_form, form_uuid: claim_id, email: 'primary@example.com',
                                  pega_status: 'Processed', created_at: 1.day.ago)

        result = provider.get_claim(claim_id)
        expect(result.dig('data', 'attributes', 'decisionLetterSent')).to be true
      end
    end

    context 'when the claim has a pending pega_status' do
      it 'sets decisionLetterSent to false in serialized attributes' do
        create(:ivc_champva_form, form_uuid: claim_id, email: 'primary@example.com',
                                  pega_status: 'pending', created_at: 1.day.ago)

        result = provider.get_claim(claim_id)
        expect(result.dig('data', 'attributes', 'decisionLetterSent')).to be_falsey
      end
    end

    context 'when the claim has a mixed-case pega_status (e.g. from polling job)' do
      ['PROCESSED', 'Processed', 'processed', 'MANUALLY PROCESSED', 'manually processed'].each do |raw_status|
        it "treats '#{raw_status}' as vbms and sets decisionLetterSent to true" do
          create(:ivc_champva_form, form_uuid: claim_id, email: 'primary@example.com',
                                    pega_status: raw_status, created_at: 1.day.ago)

          result = provider.get_claim(claim_id)
          expect(result.dig('data', 'attributes', 'decisionLetterSent')).to be true
          expect(result.dig('data', 'attributes', 'status')).to eq('vbms')
        end
      end
    end

    context 'when the claim has a mixed-case error pega_status' do
      %w[ERROR Failed REJECTED].each do |raw_status|
        it "treats '#{raw_status}' as error status" do
          create(:ivc_champva_form, form_uuid: claim_id, email: 'primary@example.com',
                                    pega_status: raw_status, created_at: 1.day.ago)

          result = provider.get_claim(claim_id)
          expect(result.dig('data', 'attributes', 'status')).to eq('error')
        end
      end
    end
  end
end
