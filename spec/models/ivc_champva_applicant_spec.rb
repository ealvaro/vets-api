# frozen_string_literal: true

require 'rails_helper'

RSpec.describe IvcChampvaApplicant, type: :model do
  describe 'validations' do
    it { is_expected.to validate_presence_of(:transaction_uuid) }
    it { is_expected.to validate_presence_of(:applicant_icn) }
    it { is_expected.to validate_presence_of(:person_type) }
  end

  describe 'factory' do
    it 'is valid with all required fields' do
      applicant = described_class.new(
        transaction_uuid: SecureRandom.uuid,
        applicant_icn: '1013836784V369083',
        person_type: 'BENEFICIARY'
      )
      expect(applicant).to be_valid
    end

    it 'is invalid without transaction_uuid' do
      applicant = described_class.new(applicant_icn: '1013836784V369083', person_type: 'BENEFICIARY')
      expect(applicant).not_to be_valid
    end

    it 'is invalid without applicant_icn' do
      applicant = described_class.new(transaction_uuid: SecureRandom.uuid, person_type: 'BENEFICIARY')
      expect(applicant).not_to be_valid
    end

    it 'is invalid without person_type' do
      applicant = described_class.new(transaction_uuid: SecureRandom.uuid, applicant_icn: '1013836784V369083')
      expect(applicant).not_to be_valid
    end
  end
end
