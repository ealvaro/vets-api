# frozen_string_literal: true

require 'rails_helper'

RSpec.describe VAOS::V2::Unified::FacilityIdTranslator do
  describe '.to_staging' do
    context 'in non-production environments' do
      it 'maps real Cheyenne (442) to staging (983)' do
        expect(described_class.to_staging('442')).to eq('983')
      end

      it 'maps real Dayton (552) to staging (984)' do
        expect(described_class.to_staging('552')).to eq('984')
      end

      it 'preserves sub-station suffixes (442GC -> 983GC)' do
        expect(described_class.to_staging('442GC')).to eq('983GC')
      end

      it 'preserves sub-station suffixes for 552 series' do
        expect(described_class.to_staging('552QA')).to eq('984QA')
      end

      it 'returns unmapped IDs unchanged' do
        expect(described_class.to_staging('668')).to eq('668')
      end

      it 'returns staging IDs unchanged (idempotent for already-staging input)' do
        expect(described_class.to_staging('983')).to eq('983')
        expect(described_class.to_staging('984')).to eq('984')
      end

      it 'returns nil for nil input' do
        expect(described_class.to_staging(nil)).to be_nil
      end

      it 'only matches at the start of the ID (does not translate interior matches)' do
        expect(described_class.to_staging('X442Y')).to eq('X442Y')
      end
    end

    context 'in production' do
      before { allow(Settings).to receive(:vsp_environment).and_return('production') }

      it 'is a no-op for known real IDs' do
        expect(described_class.to_staging('442')).to eq('442')
        expect(described_class.to_staging('552')).to eq('552')
      end

      it 'is a no-op for sub-station IDs' do
        expect(described_class.to_staging('442GC')).to eq('442GC')
      end

      it 'is a no-op for nil' do
        expect(described_class.to_staging(nil)).to be_nil
      end
    end
  end

  describe '.to_real' do
    context 'in non-production environments' do
      it 'maps staging Cheyenne (983) to real (442)' do
        expect(described_class.to_real('983')).to eq('442')
      end

      it 'maps staging Dayton (984) to real (552)' do
        expect(described_class.to_real('984')).to eq('552')
      end

      it 'preserves sub-station suffixes (983GC -> 442GC)' do
        expect(described_class.to_real('983GC')).to eq('442GC')
      end

      it 'returns unmapped IDs unchanged' do
        expect(described_class.to_real('668')).to eq('668')
      end

      it 'returns real IDs unchanged (idempotent for already-real input)' do
        expect(described_class.to_real('442')).to eq('442')
        expect(described_class.to_real('552')).to eq('552')
      end

      it 'returns nil for nil input' do
        expect(described_class.to_real(nil)).to be_nil
      end
    end

    context 'in production' do
      before { allow(Settings).to receive(:vsp_environment).and_return('production') }

      it 'is a no-op for known staging IDs' do
        expect(described_class.to_real('983')).to eq('983')
        expect(described_class.to_real('984')).to eq('984')
      end

      it 'is a no-op for nil' do
        expect(described_class.to_real(nil)).to be_nil
      end
    end
  end

  describe 'round-trip' do
    it 'real -> staging -> real returns the original ID' do
      %w[442 552 442GC 552QA].each do |original|
        round_tripped = described_class.to_real(described_class.to_staging(original))
        expect(round_tripped).to eq(original)
      end
    end

    it 'staging -> real -> staging returns the original ID' do
      %w[983 984 983GC 984QA].each do |original|
        round_tripped = described_class.to_staging(described_class.to_real(original))
        expect(round_tripped).to eq(original)
      end
    end
  end
end
