# frozen_string_literal: true

require 'rails_helper'
require 'bgs_service/benefit_claim_service'

describe ClaimsApi::BenefitClaimService do
  subject { described_class.new external_uid: 'xUid', external_key: 'xKey' }

  describe '#update_benefit_claim' do
    let(:options) do
      {
        file_number: '796163671',
        payee_code: '10',
        date_of_claim: '03/01/2013',
        claimant_ssn: '796163672',
        power_of_attorney: '002',
        benefit_claim_type: '2',
        old_end_product_code: '691',
        new_end_product_label: '690AUTRWPMC',
        old_date_of_claim: '03/01/2013'
      }
    end

    it 'updates a benefit claim' do
      VCR.use_cassette('claims_api/bgs/benefit_claim_service/update_benefit_claim') do
        result = subject.update_benefit_claim(options)

        expect(result).to be_a Hash
        expect(result[:return][:return_message]).to eq 'Update to Corporate was successful'
      end
    end
  end

  describe '#find_benefit_claim_detail' do
    let(:benefit_claim_id) { '600912467' }

    it 'returns the details of a benefit claim' do
      VCR.use_cassette('claims_api/bgs/benefit_claim_service/find_benefit_claim_detail') do
        result = subject.find_benefit_claim_detail(benefit_claim_id)

        expect(result).to be_a Hash
        expect(result.dig(:return, :benefit_claim_record, :benefit_claim_id)).to eq benefit_claim_id
      end
    end
  end

  describe '#find_benefit_claim' do
    let(:file_number) { '796163672' }

    it 'returns the benefit claims for a file number' do
      VCR.use_cassette('claims_api/bgs/benefit_claim_service/find_benefit_claim') do
        result = subject.find_benefit_claim(file_number)

        # returns hash shape of records, message records found, with selection containing claims
        expect(result).to be_a Hash
        expect(result.dig(:return, :participant_record, :return_message)).to eq 'Records found'
        expect(result.dig(:return, :participant_record, :selection)).to be_an Array
      end
    end
  end
end
