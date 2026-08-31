# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ClaimsEvidence::DocumentType do
  describe '.supported?' do
    it 'accepts an id we file evidence under' do
      expect(described_class.supported?(34)).to be(true)
    end

    it 'rejects an id we do not' do
      expect(described_class.supported?(9999)).to be(false)
    end

    it 'rejects the id as a string' do
      expect(described_class.supported?('34')).to be(false)
    end
  end

  describe '.label' do
    it 'returns the VBMS label for a supported id' do
      expect(described_class.label(34)).to eq('Correspondence')
    end

    it 'returns nil for an unsupported id' do
      expect(described_class.label(9999)).to be_nil
    end
  end

  it 'does not expose the underlying hash' do
    expect { described_class::TYPES }.to raise_error(NameError)
  end
end
