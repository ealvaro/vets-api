# frozen_string_literal: true

require 'rails_helper'

RSpec.describe RepresentationManagement::NextStepsEmailData, type: :model do
  describe 'validations' do
    subject { described_class.new }

    it { expect(subject).to validate_presence_of(:email_address) }
    it { expect(subject).to validate_presence_of(:first_name) }
    it { expect(subject).to validate_presence_of(:form_name) }
    it { expect(subject).to validate_presence_of(:form_number) }
    it { expect(subject).to validate_presence_of(:entity_type) }
    it { expect(subject).to validate_presence_of(:entity_id) }

    describe 'email_address format' do
      it 'rejects an invalid email format' do
        subject.email_address = 'not-an-email'
        subject.valid?
        expect(subject.errors[:email_address]).to be_present
      end

      it 'accepts a valid email address' do
        subject.email_address = 'veteran@example.com'
        subject.valid?
        expect(subject.errors[:email_address]).to be_empty
      end

      it 'rejects an email address over 254 characters' do
        subject.email_address = "#{'a' * 245}@example.com"
        subject.valid?
        expect(subject.errors[:email_address]).to be_present
      end
    end

    describe 'form_number inclusion' do
      it 'accepts 21-22' do
        subject.form_number = '21-22'
        subject.valid?
        expect(subject.errors[:form_number]).to be_empty
      end

      it 'accepts 21-22A' do
        subject.form_number = '21-22A'
        subject.valid?
        expect(subject.errors[:form_number]).to be_empty
      end

      it 'rejects an unrecognized form number' do
        subject.form_number = 'not-a-form'
        subject.valid?
        expect(subject.errors[:form_number]).to be_present
      end
    end

    describe 'entity_type inclusion' do
      it 'accepts individual' do
        subject.entity_type = 'individual'
        subject.valid?
        expect(subject.errors[:entity_type]).to be_empty
      end

      it 'accepts organization' do
        subject.entity_type = 'organization'
        subject.valid?
        expect(subject.errors[:entity_type]).to be_empty
      end

      it 'rejects an unrecognized entity_type' do
        subject.entity_type = 'bogus'
        subject.valid?
        expect(subject.errors[:entity_type]).to be_present
      end
    end

    describe 'entity_id length' do
      it 'rejects an entity_id over 36 characters' do
        subject.entity_id = 'a' * 37
        subject.valid?
        expect(subject.errors[:entity_id]).to be_present
      end

      it 'accepts an entity_id of 36 characters' do
        subject.entity_id = 'a' * 36
        subject.valid?
        expect(subject.errors[:entity_id]).to be_empty
      end
    end

    describe 'first_name format' do
      it 'rejects a first_name containing a newline' do
        subject.first_name = "Bob\nEvil"
        subject.valid?
        expect(subject.errors[:first_name]).to be_present
      end

      it 'rejects a first_name containing a carriage return' do
        subject.first_name = "Bob\rEvil"
        subject.valid?
        expect(subject.errors[:first_name]).to be_present
      end

      it 'accepts a first_name with Unicode characters' do
        subject.first_name = 'José María'
        subject.valid?
        expect(subject.errors[:first_name]).to be_empty
      end

      it 'rejects a first_name containing a null byte' do
        subject.first_name = "Bob\x00Evil"
        subject.valid?
        expect(subject.errors[:first_name]).to be_present
      end
    end

    describe 'form_name format' do
      it 'rejects a form_name containing a newline' do
        subject.form_name = "Form\nName"
        subject.valid?
        expect(subject.errors[:form_name]).to be_present
      end

      it 'rejects a form_name containing a null byte' do
        subject.form_name = "Form\x00Name"
        subject.valid?
        expect(subject.errors[:form_name]).to be_present
      end

      it 'accepts a form_name with normal characters' do
        subject.form_name = 'Form 21-22: Appoint a Representative'
        subject.valid?
        expect(subject.errors[:form_name]).to be_empty
      end
    end
  end

  describe '#entity' do
    it 'returns the entity for accredited_individual' do
      accredited_individual = create(:accredited_individual)
      next_steps_email_data = described_class.new(entity_type: 'individual',
                                                  entity_id: accredited_individual.registration_number)
      expect(next_steps_email_data.entity).to eq(accredited_individual)
    end

    it 'returns the entity for veteran_service_representative' do
      veteran_service_representative = create(:representative)
      next_steps_email_data = described_class.new(entity_type: 'individual',
                                                  entity_id: veteran_service_representative.representative_id)
      expect(next_steps_email_data.entity).to eq(veteran_service_representative)
    end

    it 'returns the entity for organization' do
      organization = create(:organization)
      next_steps_email_data = described_class.new(entity_type: 'organization',
                                                  entity_id: organization.poa)
      expect(next_steps_email_data.entity).to eq(organization)
    end

    it 'returns the entity for accredited_organization' do
      accredited_organization = create(:accredited_organization)
      next_steps_email_data = described_class.new(entity_type: 'organization',
                                                  entity_id: accredited_organization.id)
      expect(next_steps_email_data.entity).to eq(accredited_organization)
    end

    it 'returns nil if entity is not found' do
      next_steps_email_data = described_class.new(entity_type: 'individual', entity_id: 1)
      expect(next_steps_email_data.entity).to be_nil
    end
  end

  describe '#entity_display_type' do
    it 'returns the entity display types for AccreditedIndividual' do
      attorney = create(:accredited_individual, individual_type: 'attorney')
      claims_agent = create(:accredited_individual, individual_type: 'claims_agent')
      representative = create(:accredited_individual, individual_type: 'representative')
      next_steps_email_data_attorney =
        described_class.new(entity_type: 'individual', entity_id: attorney.registration_number)
      next_steps_email_data_claims_agent =
        described_class.new(entity_type: 'individual', entity_id: claims_agent.registration_number)
      next_steps_email_data_representative =
        described_class.new(entity_type: 'individual', entity_id: representative.registration_number)
      expect(next_steps_email_data_attorney.entity_display_type).to eq('attorney')
      expect(next_steps_email_data_claims_agent.entity_display_type).to eq('claims agent')
      expect(next_steps_email_data_representative.entity_display_type).to eq('VSO representative')
    end

    it 'returns the entity display types for Veteran::Service::Representative' do
      attorney = create(:representative, first_name: 'Bob', user_types: ['attorney'])
      claim_agents = create(:representative, first_name: 'Bobby', user_types: ['claim_agents'],
                                             representative_id: '12345')
      veteran_service_officer = create(:representative, first_name: 'Bobbie', user_types: ['veteran_service_officer'],
                                                        representative_id: '123456')
      next_steps_email_data_attorney = described_class.new(entity_type: 'individual',
                                                           entity_id: attorney.representative_id)
      next_steps_email_data_claim_agents = described_class.new(entity_type: 'individual',
                                                               entity_id: claim_agents.representative_id)
      next_steps_email_data_vso = described_class.new(entity_type: 'individual',
                                                      entity_id: veteran_service_officer.representative_id)
      expect(next_steps_email_data_attorney.entity_display_type).to eq('attorney')
      expect(next_steps_email_data_claim_agents.entity_display_type).to eq('claims agent')
      expect(next_steps_email_data_vso.entity_display_type).to eq('VSO representative')
    end

    it 'returns the entity display types for Veteran Service Organization' do
      organization = create(:organization)
      accredited_organization = create(:accredited_organization)
      next_steps_email_data_organization = described_class.new(entity_type: 'organization',
                                                               entity_id: organization.poa)
      next_steps_email_data_accredited_organization = described_class.new(entity_type: 'organization',
                                                                          entity_id: accredited_organization.id)
      expect(next_steps_email_data_organization.entity_display_type).to eq('Veterans Service Organization')
      expect(next_steps_email_data_accredited_organization.entity_display_type).to eq('Veterans Service Organization')
    end
  end

  describe '#entity_display_type with nil entity' do
    it 'returns an empty string when entity is nil' do
      next_steps_email_data = described_class.new(entity_type: 'individual', entity_id: 0)
      expect(next_steps_email_data.entity_display_type).to eq('')
    end
  end

  describe '#entity_name with nil entity' do
    it 'returns an empty string when entity is nil' do
      next_steps_email_data = described_class.new(entity_type: 'individual', entity_id: 0)
      expect(next_steps_email_data.entity_name).to eq('')
    end
  end

  describe '#entity_address with nil entity' do
    it 'returns an empty string when entity is nil' do
      next_steps_email_data = described_class.new(entity_type: 'individual', entity_id: 0)
      expect(next_steps_email_data.entity_address).to eq('')
    end
  end

  describe '#entity_name' do
    it 'returns the entity name for accredited_individual' do
      accredited_individual = create(:accredited_individual)
      next_steps_email_data = described_class.new(entity_type: 'individual',
                                                  entity_id: accredited_individual.registration_number)
      expect(next_steps_email_data.entity_name).to eq(accredited_individual.full_name)
    end

    it 'returns the entity name for veteran_service_representative' do
      veteran_service_representative = create(:representative)
      next_steps_email_data = described_class.new(entity_type: 'individual',
                                                  entity_id: veteran_service_representative.representative_id)
      expect(next_steps_email_data.entity_name).to eq(veteran_service_representative.full_name)
    end

    it 'returns the entity name for organization' do
      organization = create(:organization)
      next_steps_email_data = described_class.new(entity_type: 'organization',
                                                  entity_id: organization.poa)
      expect(next_steps_email_data.entity_name).to eq(organization.name)
    end
  end
end
