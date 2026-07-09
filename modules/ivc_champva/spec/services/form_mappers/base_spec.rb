# frozen_string_literal: true

require 'rails_helper'

RSpec.describe IvcChampva::FormMappers::Base do
  let(:test_class) do
    Class.new do
      include IvcChampva::FormMappers::Base
      public :truthy?, :name_with_suffix, :middle_initial, :format_address_string, :gender_radio
    end
  end
  let(:instance) { test_class.new }

  describe '#truthy?' do
    it 'returns true for boolean true' do
      expect(instance.truthy?(true)).to be(true)
    end

    it 'returns true for string "true"' do
      expect(instance.truthy?('true')).to be(true)
    end

    it 'returns false for boolean false' do
      expect(instance.truthy?(false)).to be(false)
    end

    it 'returns false for string "false"' do
      expect(instance.truthy?('false')).to be(false)
    end

    it 'returns false for nil' do
      expect(instance.truthy?(nil)).to be(false)
    end
  end

  describe '#name_with_suffix' do
    it 'joins last name and suffix' do
      expect(instance.name_with_suffix('Smith', 'Jr')).to eq('Smith Jr')
    end

    it 'returns just last name when suffix is nil' do
      expect(instance.name_with_suffix('Smith', nil)).to eq('Smith')
    end

    it 'returns empty string when both are nil' do
      expect(instance.name_with_suffix(nil, nil)).to eq('')
    end
  end

  describe '#middle_initial' do
    it 'returns first character' do
      expect(instance.middle_initial('Robert')).to eq('R')
    end

    it 'returns nil for nil' do
      expect(instance.middle_initial(nil)).to be_nil
    end
  end

  describe '#format_address_string' do
    it 'converts newlines' do
      expect(instance.format_address_string("123 Main St\nApt 4")).to eq('123 Main St\nApt 4')
    end

    it 'returns nil for nil' do
      expect(instance.format_address_string(nil)).to be_nil
    end
  end

  describe '#gender_radio' do
    it 'returns 0 for male' do
      expect(instance.gender_radio('male')).to eq(0)
    end

    it 'returns 1 for female' do
      expect(instance.gender_radio('female')).to eq(1)
    end

    it 'returns nil for unknown values' do
      expect(instance.gender_radio('other')).to be_nil
    end

    it 'returns nil for nil' do
      expect(instance.gender_radio(nil)).to be_nil
    end
  end
end
