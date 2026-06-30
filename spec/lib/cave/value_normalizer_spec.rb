# frozen_string_literal: true

require 'rails_helper'
require 'cave/value_normalizer'

RSpec.describe Cave::ValueNormalizer do
  describe '.canonical' do
    context 'with :name' do
      it 'reduces a raw OCR name and the normalized user hash to the same value when unchanged' do
        ocr = described_class.canonical(:name, 'JON A DOE')
        user = described_class.canonical(:name, { 'first' => 'Jon', 'middle' => 'A', 'last' => 'Doe' })
        expect(ocr).to eq(user)
      end

      it 'differs when the user corrected the name' do
        ocr = described_class.canonical(:name, 'JON A DOE')
        user = described_class.canonical(:name, { 'first' => 'John', 'middle' => 'A', 'last' => 'Doe' })
        expect(ocr).not_to eq(user)
      end
    end

    context 'with :ssn' do
      it 'compares on bare digits' do
        expect(described_class.canonical(:ssn, '123-45-6789')).to eq(described_class.canonical(:ssn, '123456789'))
      end

      it 'collapses invalid lengths to empty' do
        expect(described_class.canonical(:ssn, '12345')).to eq('')
      end
    end

    context 'with :date' do
      it 'treats MM/DD/YYYY and ISO as equal' do
        expect(described_class.canonical(:date, '04/01/1982')).to eq(described_class.canonical(:date, '1982-04-01'))
      end

      it 'collapses an unparseable date to empty' do
        expect(described_class.canonical(:date, 'unknown')).to eq('')
      end
    end

    context 'with :branch' do
      it 'maps free-text OCR to the 534 enum so an unedited branch compares equal' do
        expect(described_class.canonical(:branch, 'ARMY USAR')).to eq(described_class.canonical(:branch, 'army'))
      end

      it 'differs when the branch was changed' do
        expect(described_class.canonical(:branch, 'ARMY USAR')).not_to eq(described_class.canonical(:branch, 'navy'))
      end
    end

    context 'with :pay_grade' do
      it 'collapses an unrecognized OCR grade to empty (matching frontend normalization)' do
        expect(described_class.canonical(:pay_grade, 'E5')).to eq('')
        expect(described_class.canonical(:pay_grade, 'E-5')).to eq('E-5')
      end
    end

    context 'with :text' do
      it 'is case-insensitive and whitespace-trimmed' do
        expect(described_class.canonical(:text, ' Sergeant ')).to eq(described_class.canonical(:text, 'SERGEANT'))
      end
    end

    it 'treats nil and blank as equal across all field types' do
      %i[text name ssn date branch pay_grade character_of_service].each do |type|
        expect(described_class.canonical(type, nil)).to eq(described_class.canonical(type, ''))
      end
    end
  end

  describe '.display' do
    it 'renders a name hash as a readable full name' do
      expect(described_class.display(:name, { 'first' => 'John', 'middle' => 'A', 'last' => 'Doe' }))
        .to eq('John A Doe')
    end

    it 'renders an ISO date as MM/DD/YYYY' do
      expect(described_class.display(:date, '1982-04-01')).to eq('04/01/1982')
    end

    it 'masks/formats an SSN with dashes' do
      expect(described_class.display(:ssn, '123456789')).to eq('123-45-6789')
    end

    it 'renders a branch enum with a human label' do
      expect(described_class.display(:branch, 'navy')).to eq('Navy')
    end
  end
end
