# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Mobile::V0::Letter, type: :model do
  describe '#displayable?' do
    context 'for letters in VISIBLE_TYPES' do
      it 'returns true for benefit_summary' do
        letter = described_class.new(letter_type: 'benefit_summary', name: 'Benefit Summary Letter')
        expect(letter.displayable?).to be(true)
      end

      it 'returns true for commissary' do
        letter = described_class.new(letter_type: 'commissary', name: 'Commissary Letter')
        expect(letter.displayable?).to be(true)
      end
    end

    context 'for letters not in VISIBLE_TYPES' do
      it 'returns false for benefit_summary_dependent' do
        letter = described_class.new(letter_type: 'benefit_summary_dependent', name: 'Dependent Letter')
        expect(letter.displayable?).to be(false)
      end

      it 'returns false for certificate_of_eligibility' do
        letter = described_class.new(letter_type: 'certificate_of_eligibility', name: 'COE Letter')
        expect(letter.displayable?).to be(false)
      end
    end

    context 'for foreign_medical_program letter' do
      let(:letter) do
        described_class.new(letter_type: 'foreign_medical_program', name: 'Foreign Medical Program Letter')
      end
      let(:user) { build(:user) }

      context 'when fmp_benefits_authorization_letter_mobile flag is disabled' do
        before do
          allow(Flipper).to receive(:enabled?).with(:fmp_benefits_authorization_letter_mobile).and_return(false)
          allow(Flipper).to receive(:enabled?).with(:fmp_benefits_authorization_letter_mobile, user).and_return(false)
        end

        it 'returns false' do
          expect(letter.displayable?).to be(false)
        end

        it 'returns false for actor-aware checks' do
          expect(letter.displayable?(user)).to be(false)
        end
      end

      context 'when fmp_benefits_authorization_letter_mobile flag is enabled' do
        before do
          allow(Flipper).to receive(:enabled?).with(:fmp_benefits_authorization_letter_mobile).and_return(true)
          allow(Flipper).to receive(:enabled?).with(:fmp_benefits_authorization_letter_mobile, user).and_return(true)
        end

        it 'returns true' do
          expect(letter.displayable?).to be(true)
        end

        it 'returns true for actor-aware checks' do
          expect(letter.displayable?(user)).to be(true)
        end
      end
    end
  end

  describe 'name attribute' do
    it 'accepts the name provided' do
      letter = described_class.new(letter_type: 'commissary', name: 'Commissary Letter')
      expect(letter.name).to eq('Commissary Letter')
    end

    it 'accepts any name regardless of letter type' do
      letter = described_class.new(letter_type: 'benefit_summary', name: 'Custom Name')
      expect(letter.name).to eq('Custom Name')
    end
  end

  describe 'description attribute' do
    it 'accepts a hash description' do
      description = { 'paragraphs' => ['Some text'], 'lists' => [{ 'title' => 'Title', 'items' => ['Item 1'] }] }
      letter = described_class.new(
        letter_type: 'proof_of_service',
        name: 'Proof of Service Letter',
        description:
      )
      expect(letter.description).to eq(description)
    end

    it 'defaults to nil when description is not provided' do
      letter = described_class.new(letter_type: 'commissary', name: 'Commissary Letter')
      expect(letter.description).to be_nil
    end

    it 'accepts nil description explicitly' do
      letter = described_class.new(
        letter_type: 'service_verification',
        name: 'Service Verification Letter',
        description: nil
      )
      expect(letter.description).to be_nil
    end

    it 'accepts empty hash description' do
      letter = described_class.new(
        letter_type: 'benefit_summary',
        name: 'Benefit Summary Letter',
        description: {}
      )
      expect(letter.description).to eq({})
    end
  end

  describe 'app-version constants' do
    it 'sets CONTENT_UPDATES_APP_VERSION to the 2.78.0 descriptions-gate release' do
      expect(described_class::CONTENT_UPDATES_APP_VERSION).to eq('2.78.0')
    end

    it 'sets DESCRIPTION_CONTENT_FORMAT_APP_VERSION to the 2.80.0 rendering-support release' do
      expect(described_class::DESCRIPTION_CONTENT_FORMAT_APP_VERSION).to eq('2.80.0')
    end
  end
end
