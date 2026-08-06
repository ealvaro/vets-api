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

    context 'when no applicants have received an eligibility determination yet' do
      it 'sets decisionLetterSent to false and status to claimReceived regardless of pega_status' do
        create(:ivc_champva_form, form_uuid: claim_id, email: 'primary@example.com',
                                  pega_status: 'Processed', created_at: 1.day.ago)

        result = provider.get_claim(claim_id)
        expect(result.dig('data', 'attributes', 'decisionLetterSent')).to be false
        expect(result.dig('data', 'attributes', 'status')).to eq('claimReceived')
      end
    end

    context 'when every applicant has received an eligibility determination' do
      it 'sets decisionLetterSent to true and status to complete regardless of pega_status' do
        record = create(:ivc_champva_form, form_uuid: claim_id, transaction_uuid: SecureRandom.uuid,
                                           email: 'primary@example.com', pega_status: nil, created_at: 1.day.ago)
        create(:ivc_champva_applicant, transaction_uuid: record.transaction_uuid, eligibility_resolved: true)

        result = provider.get_claim(claim_id)
        expect(result.dig('data', 'attributes', 'decisionLetterSent')).to be true
        expect(result.dig('data', 'attributes', 'status')).to eq('complete')
      end
    end

    context 'when cst_champva_custom_content flipper is enabled' do
      before { allow(Flipper).to receive(:enabled?).with(:cst_champva_custom_content, current_user).and_return(true) }

      it 'includes claimStatusMeta in the serialized response' do
        create(:ivc_champva_form, form_uuid: claim_id, email: 'primary@example.com',
                                  pega_status: nil, created_at: 1.day.ago)

        result = provider.get_claim(claim_id)
        expect(result.dig('data', 'attributes', 'claimStatusMeta')).to be_a(Hash)
      end

      it 'claimStatusMeta.statusMap contains a claimReceived key' do
        create(:ivc_champva_form, form_uuid: claim_id, email: 'primary@example.com',
                                  pega_status: 'Received', created_at: 1.day.ago)

        result = provider.get_claim(claim_id)
        status_map = result.dig('data', 'attributes', 'claimStatusMeta', 'whatWeAreDoing', 'statusMap')
        expect(status_map).to have_key('claimReceived')
      end

      it 'claimStatusMeta.overview.currentStepByStatus maps claimReceived to step 1' do
        create(:ivc_champva_form, form_uuid: claim_id, email: 'primary@example.com',
                                  pega_status: 'Received', created_at: 1.day.ago)

        result = provider.get_claim(claim_id)
        current_step_by_status = result.dig(
          'data', 'attributes', 'claimStatusMeta', 'overview', 'currentStepByStatus'
        )
        expect(current_step_by_status['claimReceived']).to eq(1)
      end

      it 'claimStatusMeta.overview.currentStepByStatus maps complete to step 2' do
        record = create(:ivc_champva_form, form_uuid: claim_id, transaction_uuid: SecureRandom.uuid,
                                           email: 'primary@example.com', pega_status: nil, created_at: 1.day.ago)
        create(:ivc_champva_applicant, transaction_uuid: record.transaction_uuid, eligibility_resolved: true)

        result = provider.get_claim(claim_id)
        current_step_by_status = result.dig(
          'data', 'attributes', 'claimStatusMeta', 'overview', 'currentStepByStatus'
        )
        expect(current_step_by_status['complete']).to eq(2)
      end
    end

    context 'when ivc_champva_ves_eligibility_on_demand flipper is enabled' do
      before do
        allow(Flipper).to receive(:enabled?)
          .with(:ivc_champva_ves_eligibility_on_demand, current_user).and_return(true)
      end

      it 'includes applicants and sponsor at the response root instead of under claimStatusMeta' do
        record = create(:ivc_champva_form, form_uuid: claim_id, transaction_uuid: SecureRandom.uuid,
                                           email: 'primary@example.com', pega_status: nil, created_at: 1.day.ago)
        create(:ivc_champva_applicant, transaction_uuid: record.transaction_uuid, applicant_first_name: 'Jane',
                                       person_type: 'BENEFICIARY', documents_requested: true)
        IvcChampvaSponsor.create!(transaction_uuid: record.transaction_uuid, first_name: 'John')

        result = provider.get_claim(claim_id)
        applicants = result.dig('data', 'attributes', 'cstChampvaApplicants')
        expect(applicants.first).to include('firstName' => 'Jane', 'personType' => 'BENEFICIARY',
                                            'documentsRequested' => true)
        expect(result.dig('data', 'attributes', 'cstChampvaSponsor')).to include('firstName' => 'John')

        meta = result.dig('data', 'attributes', 'claimStatusMeta')
        expect(meta).to be_nil.or(satisfy { |m| !m.key?('applicants') && !m.key?('sponsor') })
      end
    end
  end

  describe '#close_date_for' do
    let(:claim_id) { SecureRandom.uuid }

    it 'returns a close_date when all applicants have eligibility resolved' do
      record = create(:ivc_champva_form, form_uuid: claim_id, transaction_uuid: SecureRandom.uuid,
                                         email: 'primary@example.com', pega_status: nil, created_at: 1.day.ago)
      create(:ivc_champva_applicant, transaction_uuid: record.transaction_uuid, eligibility_resolved: true)

      result = provider.get_claim(claim_id)
      expect(result.dig('data', 'attributes', 'closeDate')).to eq(record.updated_at.to_date.iso8601)
    end

    it 'returns nil when applicants are not yet resolved' do
      record = create(:ivc_champva_form, form_uuid: claim_id, transaction_uuid: SecureRandom.uuid,
                                         email: 'primary@example.com', pega_status: nil, created_at: 1.day.ago)
      create(:ivc_champva_applicant, transaction_uuid: record.transaction_uuid, eligibility_resolved: false)

      result = provider.get_claim(claim_id)
      expect(result.dig('data', 'attributes', 'closeDate')).to be_nil
    end

    it 'returns nil close_date for processed pega_status when no applicants exist' do
      create(:ivc_champva_form, form_uuid: claim_id, email: 'primary@example.com',
                                pega_status: 'Processed', created_at: 1.day.ago)
      result = provider.get_claim(claim_id)
      expect(result.dig('data', 'attributes', 'closeDate')).to be_nil
    end
  end
end
