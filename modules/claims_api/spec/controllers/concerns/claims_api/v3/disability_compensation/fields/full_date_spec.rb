# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ClaimsApi::V3::DisabilityCompensation::Fields::FullDate, type: :unit do
  def errors
    @errors ||= ClaimsApi::V3::DisabilityCompensation::Errors.new
  end

  def field(value)
    described_class.new(value, source: '/test/date')
  end

  describe '#validate' do
    it 'adds no error for a valid date' do
      field('2024-06-15').validate(errors:)
      expect(errors.any?).to be(false)
    end

    it 'adds an error for a calendar-impossible date' do
      field('2024-02-30').validate(errors:)
      expect(errors.messages.first[:detail]).to include('2024-02-30')
    end

    it 'does nothing for blank value' do
      field(nil).validate(errors:)
      expect(errors.any?).to be(false)
    end
  end

  describe '#valid?' do
    it 'returns true for valid date' do
      expect(field('2024-06-15').valid?).to be(true)
    end

    it 'returns false for invalid date' do
      expect(field('2024-02-30').valid?).to be(false)
    end

    it 'returns false for nil' do
      expect(field(nil).valid?).to be(false)
    end
  end

  describe '#parse' do
    it 'returns a Date object' do
      expect(field('2024-06-15').parse).to eq(Date.new(2024, 6, 15))
    end
  end
end
