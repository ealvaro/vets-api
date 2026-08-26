# frozen_string_literal: true

require 'rails_helper'

RSpec.describe IvcChampva::ChampvaLetterAllowlist do
  describe '.approved?' do
    it 'returns true for a form number exactly matching an approved entry' do
      expect(described_class.approved?('CCL-A43')).to be(true)
    end

    it 'returns true for an approved base form number with a version letter appended' do
      # CG-A01a is the approved entry; a future CG-A01b should also match, since the
      # ticket treats a trailing lowercase letter as a version indicator, not part of
      # the letter's identity.
      expect(described_class.approved?('CG-A01a')).to be(true)
      expect(described_class.approved?('CG-A01b')).to be(true)
      expect(described_class.approved?('CG-A01z')).to be(true)
    end

    it 'returns true for an approved form number with a VES-appended suffix after a literal period' do
      expect(described_class.approved?('CCL-A43a.ENC')).to be(true)
    end

    it 'returns true for an approved entry that has no version letter at all' do
      expect(described_class.approved?('CVA-SBL01')).to be(true)
    end

    it 'returns false for an unrelated form number that merely shares an approved prefix' do
      # CG-A99z shares the CG- prefix with the approved CG-A01a/CG-A02a, but its own
      # base (CG-A99) is not on the allowlist -- prefix alone must not be sufficient,
      # per the ticket's explicit warning about CG scope.
      expect(described_class.approved?('CG-A99z')).to be(false)
      expect(described_class.approved?('CCL-Z99z')).to be(false)
      expect(described_class.approved?('CVA-ZZZ99')).to be(false)
    end

    it 'returns false for an unknown or unrelated letter type' do
      expect(described_class.approved?('742-801')).to be(false)
      expect(described_class.approved?('NEW-001')).to be(false)
    end

    it 'returns false for blank input' do
      expect(described_class.approved?(nil)).to be(false)
      expect(described_class.approved?('')).to be(false)
      expect(described_class.approved?('   ')).to be(false)
    end

    it 'is case-insensitive on the base form number' do
      expect(described_class.approved?('ccl-a43')).to be(true)
    end

    it 'does not fold an uppercase trailing letter into a lowercase version-letter match' do
      # 'Ccl-A43A.enc' has an uppercase trailing 'A'. Per .normalize's documented intent, only
      # a trailing *lowercase* letter is treated as a version indicator to strip -- an uppercase
      # one is left as part of the identity, so this does not silently collapse into the
      # approved 'CCL-A43'/'CCL-A43a' entries the way a same-case trailing letter would.
      expect(described_class.approved?('Ccl-A43A.enc')).to be(false)
    end
  end

  describe '.normalize' do
    it 'strips a trailing lowercase version letter' do
      expect(described_class.normalize('CG-A01a')).to eq('cg-a01')
    end

    it 'strips a suffix after a literal period' do
      expect(described_class.normalize('CCL-A43a.ENC')).to eq('ccl-a43')
    end

    it 'leaves a form number with no version letter or suffix unchanged (aside from case)' do
      expect(described_class.normalize('CVA-SBL01')).to eq('cva-sbl01')
    end

    it 'returns nil for blank input' do
      expect(described_class.normalize(nil)).to be_nil
      expect(described_class.normalize('')).to be_nil
    end
  end

  describe 'APPROVED_FORM_NUMBERS' do
    it 'is loaded and non-empty' do
      expect(described_class::APPROVED_FORM_NUMBERS).not_to be_empty
    end

    it 'contains only normalized (lowercased, version-letter-stripped) entries' do
      expect(described_class::APPROVED_FORM_NUMBERS).to all(
        satisfy { |entry| entry == described_class.normalize(entry) }
      )
    end
  end
end
