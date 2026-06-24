# frozen_string_literal: true

require 'rails_helper'

RSpec.describe TravelPay::MileageExpense, type: :model do
  let(:valid_attributes) do
    {
      purchase_date: Time.current,
      trip_type: 'OneWay'
    }
  end

  describe 'inheritance' do
    it 'inherits from BaseExpense' do
      expect(described_class.superclass).to eq(TravelPay::BaseExpense)
    end
  end

  describe 'constants' do
    it 'uses TRIP_TYPES from Constants module' do
      expect(TravelPay::Constants::TRIP_TYPES.values).to eq(%w[OneWay RoundTrip Unspecified])
    end
  end

  describe 'validations' do
    subject { described_class.new(valid_attributes) }

    context 'trip_type validation' do
      it 'requires trip_type to be present' do
        subject.trip_type = nil
        expect(subject).not_to be_valid
        expect(subject.errors[:trip_type]).to include("can't be blank")
      end

      it 'requires trip_type to be in valid options' do
        subject.trip_type = 'INVALID_TYPE'
        expect(subject).not_to be_valid
        expect(subject.errors[:trip_type]).to include('is not included in the list')
      end

      it 'accepts valid trip_type values' do
        subject.trip_type = 'OneWay'
        expect(subject).to be_valid

        subject.trip_type = 'RoundTrip'
        expect(subject).to be_valid

        subject.trip_type = 'Unspecified'
        expect(subject).to be_valid
      end

      it 'rejects invalid casing' do
        subject.trip_type = 'one_way'
        expect(subject).not_to be_valid
        expect(subject.errors[:trip_type]).to include('is not included in the list')

        subject.trip_type = 'ONE_WAY'
        expect(subject).not_to be_valid
        expect(subject.errors[:trip_type]).to include('is not included in the list')
      end
    end
  end

  describe '#expense_type' do
    subject { described_class.new(valid_attributes) }

    it 'returns "mileage" as the expense type' do
      expect(subject.expense_type).to eq('mileage')
    end
  end

  describe '#to_h' do
    subject { described_class.new(valid_attributes.merge(claim_id: 'claim-123')) }

    it 'returns a hash representation including mileage-specific attributes' do
      json = subject.to_h
      expect(json['trip_type']).to eq('OneWay')
      expect(json['expense_type']).to eq('mileage')
    end

    it 'includes inherited BaseExpense attributes' do
      json = subject.to_h
      expect(json['claim_id']).to eq('claim-123')
      expect(json['has_receipt']).to be false
    end
  end

  describe 'instantiation scenarios' do
    context 'creating a mileage expense with all attributes' do
      let(:expense) do
        described_class.new(
          purchase_date: Date.current,
          trip_type: 'RoundTrip',
          claim_id: 'uuid-123'
        )
      end

      it 'creates a valid mileage expense' do
        expect(expense).to be_valid
        expect(expense.trip_type).to eq('RoundTrip')
        expect(expense.claim_id).to eq('uuid-123')
        expect(expense.expense_type).to eq('mileage')
      end
    end
  end

  describe '.permitted_params' do
    let(:user) { build(:user) }

    context 'when travel_pay_enable_one_way_mileage is disabled' do
      before do
        allow(Flipper).to receive(:enabled?).with(:travel_pay_enable_one_way_mileage, user).and_return(false)
      end

      it 'returns base mileage-specific permitted parameters' do
        params = described_class.permitted_params(user)
        expect(params).to eq(%i[purchase_date trip_type description])
      end

      it 'does not include address params' do
        params = described_class.permitted_params(user)
        expect(params).not_to include(a_hash_including(:start_address))
        expect(params).not_to include(a_hash_including(:end_address))
      end
    end

    context 'when travel_pay_enable_one_way_mileage is enabled' do
      before do
        allow(Flipper).to receive(:enabled?).with(:travel_pay_enable_one_way_mileage, user).and_return(true)
      end

      it 'includes address params' do
        params = described_class.permitted_params(user)
        address_hash = params.find { |p| p.is_a?(Hash) }
        expect(address_hash).to include(
          start_address: %i[address_line1 address_line2 city state_code postal_code],
          end_address: %i[address_line1 address_line2 city state_code postal_code]
        )
      end

      it 'still includes base params' do
        params = described_class.permitted_params(user)
        expect(params).to include(:purchase_date, :trip_type, :description)
      end
    end

    it 'does not include cost_requested or receipt' do
      params = described_class.permitted_params
      expect(params).not_to include(:cost_requested)
      expect(params).not_to include(:receipt)
    end

    it 'overrides the base class permitted_params' do
      expect(described_class.permitted_params).not_to eq(TravelPay::BaseExpense.permitted_params)
    end
  end

  describe '#to_service_params' do
    subject do
      expense = described_class.new(
        purchase_date: Date.new(2024, 3, 15),
        trip_type: 'RoundTrip',
        claim_id: 'claim-uuid-456'
      )
      expense.user = user
      expense
    end

    let(:user) { build(:user) }

    it 'returns a hash with expense_type' do
      params = subject.to_service_params
      expect(params['expense_type']).to eq('mileage')
    end

    it 'includes purchase_date' do
      params = subject.to_service_params
      expect(params['purchase_date']).to eq('2024-03-15')
    end

    it 'includes trip_type' do
      params = subject.to_service_params
      expect(params['trip_type']).to eq('RoundTrip')
    end

    it 'includes claim_id when present' do
      params = subject.to_service_params
      expect(params['claim_id']).to eq('claim-uuid-456')
    end

    it 'excludes claim_id when nil' do
      subject.claim_id = nil
      params = subject.to_service_params
      expect(params).not_to have_key('claim_id')
    end

    it 'does include description' do
      params = subject.to_service_params
      expect(params).to have_key('description')
    end

    context 'when travel_pay_enable_one_way_mileage is disabled' do
      before do
        allow(Flipper).to receive(:enabled?).with(:travel_pay_enable_one_way_mileage, user).and_return(false)
      end

      it 'excludes start_address and end_address even when set' do
        subject.start_address = { 'address_line1' => '123 Main St', 'city' => 'Anytown',
                                  'state_code' => 'VA', 'postal_code' => '22030' }
        subject.end_address = { 'address_line1' => '456 Oak Ave', 'city' => 'Othertown',
                                'state_code' => 'MD', 'postal_code' => '20910' }
        params = subject.to_service_params
        expect(params).not_to have_key('start_address')
        expect(params).not_to have_key('end_address')
      end
    end

    context 'when travel_pay_enable_one_way_mileage is enabled' do
      before do
        allow(Flipper).to receive(:enabled?).with(:travel_pay_enable_one_way_mileage, user).and_return(true)
      end

      it 'includes start_address when present' do
        subject.start_address = { 'address_line1' => '123 Main St', 'city' => 'Anytown',
                                  'state_code' => 'VA', 'postal_code' => '22030' }
        params = subject.to_service_params
        expect(params['start_address']).to include('address_line1' => '123 Main St')
      end

      it 'includes end_address when present' do
        subject.end_address = { 'address_line1' => '456 Oak Ave', 'city' => 'Othertown',
                                'state_code' => 'MD', 'postal_code' => '20910' }
        params = subject.to_service_params
        expect(params['end_address']).to include('address_line1' => '456 Oak Ave')
      end

      it 'excludes start_address when nil' do
        subject.start_address = nil
        params = subject.to_service_params
        expect(params).not_to have_key('start_address')
      end

      it 'excludes end_address when nil' do
        subject.end_address = nil
        params = subject.to_service_params
        expect(params).not_to have_key('end_address')
      end
    end
  end
end
