# frozen_string_literal: true

require 'rails_helper'

RSpec.describe RepresentationManagement::Form2122Base, type: :model do
  describe 'after_validation logging' do
    let(:monitor) { instance_double(RepresentationManagement::Monitor, track_validation_errors: nil) }
    let(:valid_veteran_attributes) do
      {
        veteran_first_name: 'John',
        veteran_last_name: 'Veteran',
        veteran_social_security_number: '123456789',
        veteran_date_of_birth: '1980-12-31',
        veteran_address_line1: '123 Main St',
        veteran_city: 'Portland',
        veteran_country: 'US',
        veteran_state_code: 'OR',
        veteran_zip_code: '97201'
      }
    end

    before do
      allow(RepresentationManagement::Monitor).to receive(:new).and_return(monitor)
      allow(Flipper).to receive(:enabled?).and_call_original
    end

    context 'when form2122_validation_error_logging is enabled' do
      before do
        allow(Flipper).to receive(:enabled?).with(:form2122_validation_error_logging).and_return(true)
      end

      it 'logs validation errors after validation fails' do
        form = described_class.new(valid_veteran_attributes.merge(veteran_first_name: nil))

        form.valid?

        expect(monitor).to have_received(:track_validation_errors).with(
          hash_including(
            message: 'Representation management base form validation failed',
            errors: hash_including(veteran_first_name: include("can't be blank")),
            form_id: '21-22'
          )
        )
      end

      it 'does not log when validation passes with no errors' do
        form = described_class.new(**valid_veteran_attributes)

        form.valid?

        expect(monitor).not_to have_received(:track_validation_errors)
      end
    end

    context 'when form2122_validation_error_logging is disabled' do
      before do
        allow(Flipper).to receive(:enabled?).with(:form2122_validation_error_logging).and_return(false)
      end

      it 'does not log validation errors after validation fails' do
        form = described_class.new(valid_veteran_attributes.merge(veteran_first_name: nil))

        form.valid?

        expect(monitor).not_to have_received(:track_validation_errors)
      end
    end
  end

  describe 'validations' do
    subject { described_class.new(**valid_veteran_attributes) }

    let(:valid_veteran_attributes) do
      {
        veteran_first_name: 'John',
        veteran_last_name: 'Veteran',
        veteran_social_security_number: '123456789',
        veteran_date_of_birth: '1980-12-31',
        veteran_address_line1: '123 Main St',
        veteran_city: 'Portland',
        veteran_country: 'US',
        veteran_state_code: 'OR',
        veteran_zip_code: '97201'
      }
    end

    let(:subject_with_claimant) do
      described_class.new(
        veteran_first_name: 'John',
        veteran_last_name: 'Veteran',
        veteran_social_security_number: '123456789',
        veteran_date_of_birth: '1980-12-31',
        veteran_address_line1: '123 Main St',
        veteran_city: 'Portland',
        veteran_country: 'US',
        veteran_state_code: 'OR',
        veteran_zip_code: '97201',
        claimant_first_name: 'John',
        claimant_last_name: 'Claimant',
        claimant_date_of_birth: '1980-12-31',
        claimant_relationship: 'Spouse',
        claimant_address_line1: '456 Main St',
        claimant_city: 'Portland',
        claimant_country: 'US',
        claimant_state_code: 'OR',
        claimant_zip_code: '97201',
        claimant_phone: '5555555555'
      )
    end

    it { expect(subject).to validate_presence_of(:veteran_first_name) }
    it { expect(subject).to validate_length_of(:veteran_first_name).is_at_most(12) }
    it { expect(subject).to validate_length_of(:veteran_middle_initial).is_at_most(1) }
    it { expect(subject).to validate_presence_of(:veteran_last_name) }
    it { expect(subject).to validate_length_of(:veteran_last_name).is_at_most(18) }
    it { expect(subject).to validate_presence_of(:veteran_social_security_number) }
    it { expect(subject).to allow_value('123456789').for(:veteran_social_security_number) }
    it { expect(subject).not_to allow_value('12345678A').for(:veteran_social_security_number) }
    it { expect(subject).not_to allow_value('12345678').for(:veteran_social_security_number) }
    it { expect(subject).not_to allow_value('1234567890').for(:veteran_social_security_number) }
    it { expect(subject).to allow_value('123456789').for(:veteran_va_file_number) }
    it { expect(subject).not_to allow_value('12345678').for(:veteran_va_file_number) }
    it { expect(subject).not_to allow_value('1234567890').for(:veteran_va_file_number) }
    it { expect(subject).to validate_presence_of(:veteran_date_of_birth) }
    it { expect(subject).to validate_presence_of(:veteran_address_line1) }
    it { expect(subject).to validate_length_of(:veteran_address_line1).is_at_most(30) }
    it { expect(subject).to validate_length_of(:veteran_address_line2).is_at_most(5) }
    it { expect(subject).to validate_presence_of(:veteran_city) }
    it { expect(subject).to validate_length_of(:veteran_city).is_at_most(18) }
    it { expect(subject).to validate_presence_of(:veteran_country) }
    it { expect(subject).to validate_length_of(:veteran_country).is_equal_to(2) }
    it { expect(subject).to validate_presence_of(:veteran_state_code) }
    it { expect(subject).to validate_length_of(:veteran_state_code).is_at_least(2) }
    it { expect(subject).to allow_value('Kansas').for(:veteran_state_code) }
    it { expect(subject).not_to allow_value('K').for(:veteran_state_code) }
    it { expect(subject).to validate_presence_of(:veteran_zip_code) }
    it { expect(subject).to allow_value('12345').for(:veteran_zip_code) }
    it { expect(subject).to allow_value('1234').for(:veteran_zip_code_suffix) }
    it { expect(subject).to allow_value('').for(:veteran_zip_code_suffix) }
    it { expect(subject).to allow_value('1234567890').for(:veteran_phone) }
    it { expect(subject).not_to allow_value('123456789A').for(:veteran_phone) }
    it { expect(subject).not_to allow_value('123456789').for(:veteran_phone) }
    it { expect(subject).to allow_value('AA12345').for(:veteran_service_number) }
    it { expect(subject).not_to allow_value('123456789').for(:veteran_service_number) }
    it { expect(subject).not_to allow_value('1234567890').for(:veteran_service_number) }
    it { expect(subject_with_claimant).to validate_length_of(:claimant_first_name).is_at_most(12) }
    it { expect(subject_with_claimant).to validate_presence_of(:claimant_last_name) }
    it { expect(subject_with_claimant).to validate_length_of(:claimant_last_name).is_at_most(18) }
    it { expect(subject_with_claimant).to validate_presence_of(:claimant_date_of_birth) }
    it { expect(subject_with_claimant).to validate_presence_of(:claimant_relationship) }
    it { expect(subject_with_claimant).to validate_presence_of(:claimant_address_line1) }
    it { expect(subject_with_claimant).to validate_length_of(:claimant_address_line1).is_at_most(30) }
    it { expect(subject_with_claimant).to validate_length_of(:claimant_address_line2).is_at_most(5) }
    it { expect(subject_with_claimant).to validate_presence_of(:claimant_city) }
    it { expect(subject_with_claimant).to validate_length_of(:claimant_city).is_at_most(18) }
    it { expect(subject_with_claimant).to validate_presence_of(:claimant_country) }
    it { expect(subject_with_claimant).to validate_length_of(:claimant_country).is_equal_to(2) }
    it { expect(subject_with_claimant).to validate_presence_of(:claimant_state_code) }
    it { expect(subject_with_claimant).to validate_length_of(:claimant_state_code).is_at_least(2) }
    it { expect(subject_with_claimant).to allow_value('Kansas').for(:claimant_state_code) }
    it { expect(subject_with_claimant).not_to allow_value('K').for(:claimant_state_code) }
    it { expect(subject_with_claimant).to validate_presence_of(:claimant_zip_code) }
    it { expect(subject_with_claimant).to allow_value('12345').for(:claimant_zip_code) }
    it { expect(subject_with_claimant).to allow_value('1234').for(:claimant_zip_code_suffix) }
    it { expect(subject_with_claimant).to allow_value('').for(:claimant_zip_code_suffix) }
    it { expect(subject_with_claimant).to allow_value('1234567890').for(:claimant_phone) }
    it { expect(subject_with_claimant).not_to allow_value('123456789A').for(:claimant_phone) }
    it { expect(subject_with_claimant).not_to allow_value('123456789').for(:claimant_phone) }

    describe 'conditional state/zip validations for international addresses' do
      it 'does not require veteran_state_code or veteran_zip_code for international veteran addresses' do
        form = described_class.new(
          veteran_first_name: 'John',
          veteran_last_name: 'Veteran',
          veteran_social_security_number: '123456789',
          veteran_date_of_birth: '1980-12-31',
          veteran_address_line1: '123 Fake Veteran St',
          veteran_city: 'London',
          veteran_country: 'GB',
          veteran_state_code: nil,
          veteran_zip_code: nil
        )

        form.validate

        expect(form.errors[:veteran_state_code]).to be_empty
        expect(form.errors[:veteran_zip_code]).to be_empty
        expect { form.veteran_state_code_truncated }.not_to raise_error
        expect(form.veteran_state_code_truncated).to eq('')
        expect { form.veteran_zip_code_expanded }.not_to raise_error
        expect(form.veteran_zip_code_expanded).to eq(['', ''])
      end

      it 'does not require claimant_state_code or claimant_zip_code for international claimant addresses' do
        form = described_class.new(
          claimant_first_name: 'John',
          claimant_last_name: 'Claimant',
          claimant_date_of_birth: '1980-12-31',
          claimant_relationship: 'Spouse',
          claimant_address_line1: '123 Fake Claimant St',
          claimant_city: 'London',
          claimant_country: 'GB',
          claimant_phone: '5555555555',
          claimant_state_code: nil,
          claimant_zip_code: nil
        )

        form.validate

        expect(form.errors[:claimant_state_code]).to be_empty
        expect(form.errors[:claimant_zip_code]).to be_empty
        expect { form.claimant_state_code_truncated }.not_to raise_error
        expect(form.claimant_state_code_truncated).to eq('')
        expect { form.claimant_zip_code_expanded }.not_to raise_error
        expect(form.claimant_zip_code_expanded).to eq(['', ''])
      end
    end

    describe 'representative_phone' do
      context 'when representative is an instance of AccreditedIndividual' do
        it 'returns #phone of the representative' do
          representative = create(:accredited_individual, phone: '5555555555')
          subject.representative_id = representative.id
          expect(subject.representative_phone).to eq(representative.phone)
        end
      end

      context 'when representative is an instance of Veteran::Service::Representative' do
        before do
          allow(Flipper).to receive(:enabled?).and_call_original
          allow(Flipper).to receive(:enabled?)
            .with(:arc_appoint_a_representative_use_accredited_models).and_return(false)
        end

        it 'returns #phone_number of the representative' do
          representative = create(:representative, phone_number: '5555555555')
          subject.representative_id = representative.representative_id
          expect(subject.representative_phone).to eq(representative.phone_number)
        end
      end
    end

    describe 'representative_individual_type' do
      context 'when representative is an instance of AccreditedIndividual' do
        it 'returns #individual_type of the representative' do
          representative = create(:accredited_individual, individual_type: 'attorney')
          subject.representative_id = representative.id
          expect(subject.representative_individual_type).to eq(representative.individual_type)
        end

        it 'returns "agent" if individual_type includes "agent"' do
          representative = create(:accredited_individual, individual_type: 'claims_agent')
          subject.representative_id = representative.id
          expect(subject.representative_individual_type).to eq('agent')
        end
      end

      context 'when representative is an instance of Veteran::Service::Representative' do
        before do
          allow(Flipper).to receive(:enabled?).and_call_original
          allow(Flipper).to receive(:enabled?)
            .with(:arc_appoint_a_representative_use_accredited_models).and_return(false)
        end

        it 'returns the first element in the user_types array' do
          representative = create(:representative, user_types: %w[attorney claim_agents])
          subject.representative_id = representative.representative_id
          expect(subject.representative_individual_type).to eq(representative.user_types.first)
        end

        it 'returns nil if user_types is empty' do
          representative = create(:representative, user_types: [])
          subject.representative_id = representative.representative_id
          expect(subject.representative_individual_type).to be_nil
        end
      end
    end

    describe 'veteran_state_code_truncated' do
      it 'truncates the state code to 2 characters if it is longer' do
        subject.veteran_state_code = 'Kansas'
        expect(subject.veteran_state_code_truncated).to eq('Ka')
      end

      it 'does not truncate the state code if it is 2 characters' do
        subject.veteran_state_code = 'KS'
        expect(subject.veteran_state_code_truncated).to eq('KS')
      end

      it 'returns an empty string when the state code is nil' do
        subject.veteran_state_code = nil
        expect(subject.veteran_state_code_truncated).to eq('')
      end
    end

    describe 'claimant_state_code_truncated' do
      it 'truncates the state code to 2 characters if it is longer' do
        subject.claimant_state_code = 'Kansas'
        expect(subject.claimant_state_code_truncated).to eq('Ka')
      end

      it 'does not truncate the state code if it is 2 characters' do
        subject.claimant_state_code = 'KS'
        expect(subject.claimant_state_code_truncated).to eq('KS')
      end

      it 'returns an empty string when the state code is nil' do
        subject.claimant_state_code = nil
        expect(subject.claimant_state_code_truncated).to eq('')
      end
    end

    describe 'veteran_zip_code_expanded' do
      it 'returns the zip code and suffix as separate elements if suffix is present' do
        subject.veteran_zip_code = '12345'
        subject.veteran_zip_code_suffix = '6789'
        expect(subject.veteran_zip_code_expanded).to eq(%w[12345 6789])
      end

      it 'returns the zip code and suffix as separate elements if suffix is not present' do
        subject.veteran_zip_code = '12345'
        expect(subject.veteran_zip_code_expanded).to eq(['12345', ''])
      end

      it 'overflows zip/postal codes longer than 5 characters into the suffix' do
        subject.veteran_zip_code = '123456'
        expect(subject.veteran_zip_code_expanded).to eq(%w[12345 6])
      end

      it 'returns blank zip components when the zip code is nil' do
        subject.veteran_zip_code = nil
        subject.veteran_zip_code_suffix = nil
        expect(subject.veteran_zip_code_expanded).to eq(['', ''])
      end
    end

    describe 'claimant_zip_code_expanded' do
      it 'returns the zip code and suffix as separate elements if suffix is present' do
        subject.claimant_zip_code = '12345'
        subject.claimant_zip_code_suffix = '6789'
        expect(subject.claimant_zip_code_expanded).to eq(%w[12345 6789])
      end

      it 'returns the zip code and suffix as separate elements if suffix is not present' do
        subject.claimant_zip_code = '12345'
        expect(subject.claimant_zip_code_expanded).to eq(['12345', ''])
      end

      it 'overflows zip/postal codes longer than 5 characters into the suffix' do
        subject.claimant_zip_code = '123456'
        expect(subject.claimant_zip_code_expanded).to eq(%w[12345 6])
      end

      it 'returns blank zip components when the zip code is nil' do
        subject.claimant_zip_code = nil
        subject.claimant_zip_code_suffix = nil
        expect(subject.claimant_zip_code_expanded).to eq(['', ''])
      end
    end

    # Custom validation tests
    context 'consent_limits_must_contain_valid_values' do
      it 'is not valid if consent_limits contains invalid values' do
        subject.consent_limits = ['alcolholism'] # Not fully capitalized
        subject.send(:consent_limits_must_contain_valid_values)
        expect(subject.errors[:consent_limits].first).to include('is not a valid limitation of consent')
      end

      it 'is not valid if there are a mix of valid and invalid values' do
        subject.consent_limits = %w[ALCOHOLISM drug_abuse] # Not fully capitalized
        subject.send(:consent_limits_must_contain_valid_values)
        expect(subject.errors[:consent_limits].first).to include('is not a valid limitation of consent')
      end

      it 'is valid if consent_limits contains valid values' do
        subject.consent_limits = ['ALCOHOLISM']
        subject.send(:consent_limits_must_contain_valid_values)
        expect(subject.errors[:consent_limits]).to be_empty
      end

      it 'is valid if multiple valid values are present' do
        subject.consent_limits = %w[ALCOHOLISM DRUG_ABUSE]
        subject.send(:consent_limits_must_contain_valid_values)
        expect(subject.errors[:consent_limits]).to be_empty
      end
    end
  end
end
