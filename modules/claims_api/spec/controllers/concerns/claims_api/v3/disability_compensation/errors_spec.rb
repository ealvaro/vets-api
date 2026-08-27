# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ClaimsApi::V3::DisabilityCompensation::Errors, type: :unit do
  subject(:errors) { described_class.new(base_source: '/test') }

  describe '#add' do
    it 'prepends base_source to the source' do
      errors.add(source: '/field', detail: 'bad')
      expect(errors.messages.first[:source]).to eq('/test/field')
    end
  end

  describe '#merge' do
    it 'combines messages from another Errors instance' do
      other = described_class.new
      other.add(source: '/other', detail: 'also bad')
      errors.add(source: '/first', detail: 'bad')
      errors.merge(other)
      expect(errors.messages.size).to eq(2)
    end
  end

  describe '#any?' do
    it('empty') { expect(errors.any?).to be(false) }

    it 'with errors' do
      errors.add(source: '/', detail: 'x')
      expect(errors.any?).to be(true)
    end
  end

  describe '#presence' do
    it 'returns nil when empty' do
      expect(errors.presence).to be_nil
    end

    it 'returns messages when errors exist' do
      errors.add(source: '/f', detail: 'bad')
      expect(errors.presence).to eq(errors.messages)
    end
  end
end
