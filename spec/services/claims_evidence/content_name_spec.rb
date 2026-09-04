# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ClaimsEvidence::ContentName do
  # Validated against the vendored CE schema rather than a pattern written here, which would only
  # assert that sanitize agrees with itself. Note the vendored copy is more permissive than the
  # live service -- it reads `&-_` as a range where CE reads three literals -- so passing this is
  # necessary but not sufficient. CE refuses anything outside its own pattern with 400
  # VEFSERR40003, confirmed on staging 08/30/2026.
  let(:ce_schema) do
    JSON.parse(
      Rails.root.join('modules', 'claims_evidence_api', 'lib', 'claims_evidence_api',
                      'schema', 'properties', 'contentName.json').read
    )
  end

  def accepted_by_ce?(name)
    JSON::Validator.fully_validate(ce_schema, name).empty?
  end

  describe '.sanitize' do
    it 'leaves a name Claims Evidence already accepts alone' do
      expect(described_class.sanitize('DD214.pdf')).to eq('DD214.pdf')
    end

    it 'keeps spaces, which the pattern allows' do
      expect(described_class.sanitize('Scanned Document.pdf')).to eq('Scanned Document.pdf')
    end

    it 'transliterates accents rather than stripping the letters' do
      expect(described_class.sanitize('José récords 50%.pdf')).to eq('Jose records 50.pdf')
    end

    it 'lowercases the extension' do
      expect(described_class.sanitize('my scan (1).PDF')).to eq('my scan (1).pdf')
    end

    it 'collapses the whitespace a stripped character leaves behind' do
      expect(described_class.sanitize('  spaced   out  .txt')).to eq('spaced out.txt')
    end

    # A script with no ASCII equivalent transliterates to "???" and then strips to nothing, which
    # is reported rather than substituted with an invented name.
    it 'raises when nothing usable survives' do
      ['日本語.pdf', '   .pdf', '???.pdf'].each do |name|
        expect { described_class.sanitize(name) }.to raise_error(described_class::Unsupported), name
      end
    end

    it 'raises ArgumentError when the caller skipped extension validation' do
      expect { described_class.sanitize('report.superlongext') }.to raise_error(ArgumentError)
    end

    it 'truncates to the 256 character limit' do
      result = described_class.sanitize("#{'a' * 300}.pdf")

      expect(result.length).to eq(256)
      expect(result).to end_with('.pdf')
    end

    it 'produces something inside the pattern for every name we accept' do
      %w[DD214.pdf scan.jpeg photo.PNG notes.txt records.tiff].each do |name|
        expect(accepted_by_ce?(described_class.sanitize(name))).to be(true), name
      end
    end

    it 'produces something inside the pattern for names we would otherwise send raw' do
      ['José récords 50%.pdf', 'my scan (1).PDF', "#{'a' * 300}.pdf",
       'report; drop table.pdf'].each do |name|
        expect(accepted_by_ce?(described_class.sanitize(name))).to be(true), name
      end
    end
  end
end
