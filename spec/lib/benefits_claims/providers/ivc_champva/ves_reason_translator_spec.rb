# frozen_string_literal: true

require 'rails_helper'

RSpec.describe BenefitsClaims::Providers::IvcChampva::VesReasonTranslator do
  before do
    allow(StatsD).to receive(:increment)
  end

  describe '.translate' do
    it 'substitutes the first name into a bare-string reason entry' do
      result = described_class.translate('certified cg', 'Jane')

      expect(result).to include('We mailed Jane a welcome letter')
    end

    it "falls back to 'The applicant' when no first name is given" do
      result = described_class.translate('certified cg')

      expect(result).to include('We mailed The applicant a welcome letter')
    end

    it 'returns the text (not the link) for a hash reason entry' do
      result = described_class.translate('tricare eligible', 'Jane')

      expect(result).to include("Jane's not eligible for CHAMPVA benefits because they’re eligible for TRICARE")
    end

    it 'is case- and whitespace-insensitive on the raw code' do
      result = described_class.translate('  Certified CG  ', 'Jane')

      expect(result).to include('We mailed Jane a welcome letter')
    end

    it 'returns nil for a blank raw_reason without tracking it as unmapped' do
      expect(described_class.translate(nil)).to be_nil
      expect(described_class.translate('')).to be_nil
      expect(StatsD).not_to have_received(:increment)
    end

    it 'returns nil for a known code whose value is intentionally null, without tracking it as unmapped' do
      result = described_class.translate('died of sc disability', 'Jane')

      expect(result).to be_nil
      expect(StatsD).not_to have_received(:increment)
        .with('ivc_champva.eligibility.ves_reason_code_unmapped', anything)
    end

    it 'returns nil and tracks a truly unmapped code' do
      expect(Rails.logger).to receive(:warn).with(
        '[BenefitsClaims::Providers::IvcChampva::VesReasonTranslator] Unmapped VES reason code',
        { raw_reason: 'SOME NEW VES CODE' }
      )

      result = described_class.translate('SOME NEW VES CODE', 'Jane')

      expect(result).to be_nil
      expect(StatsD).to have_received(:increment)
        .with('ivc_champva.eligibility.ves_reason_code_unmapped', tags: ['reason:some new ves code'])
    end

    it "strips ':' from an unmapped code before it reaches the StatsD tag" do
      # raw_reason is external, VES-controlled input -- unlike the 'context:' tags elsewhere
      # in this file, we can't assume it's colon-free (see ConfigFileLoader.sanitize_tag_value).
      described_class.translate('SOME: NEW CODE', 'Jane')

      expect(StatsD).to have_received(:increment)
        .with('ivc_champva.eligibility.ves_reason_code_unmapped', tags: ['reason:some new code'])
    end
  end

  describe '.link_for' do
    it 'returns nil for a bare-string reason entry' do
      expect(described_class.link_for('certified cg')).to be_nil
    end

    it 'returns the link hash for a reason entry that has one' do
      link = described_class.link_for('tricare eligible')

      expect(link).to eq(
        'text' => 'Learn more about TRICARE eligibility on the TRICARE website',
        'url' => 'https://www.tricare.mil/Plans/Eligibility'
      )
    end

    it 'returns nil for a blank raw_reason' do
      expect(described_class.link_for(nil)).to be_nil
    end

    it 'returns nil for an unmapped code' do
      expect(described_class.link_for('SOME NEW VES CODE')).to be_nil
    end
  end
end
