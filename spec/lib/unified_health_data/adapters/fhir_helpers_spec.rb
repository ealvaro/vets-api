# frozen_string_literal: true

require 'rails_helper'
require 'unified_health_data/adapters/fhir_helpers'

describe UnifiedHealthData::Adapters::FhirHelpers do
  # Create a test class that includes the module
  subject { helper_class.new }

  let(:helper_class) do
    Class.new do
      include UnifiedHealthData::Adapters::FhirHelpers
    end
  end

  describe '#find_identifier_value' do
    let(:identifiers) do
      [
        { 'type' => { 'text' => 'Tracking Number' }, 'value' => 'TRK123' },
        { 'type' => { 'text' => 'Prescription Number' }, 'value' => 'RX456' },
        { 'type' => { 'text' => 'Carrier' }, 'value' => 'USPS' }
      ]
    end

    it 'finds identifier value by type text' do
      result = subject.find_identifier_value(identifiers, 'Tracking Number')
      expect(result).to eq('TRK123')
    end

    it 'returns nil when type text not found' do
      result = subject.find_identifier_value(identifiers, 'Unknown Type')
      expect(result).to be_nil
    end

    it 'returns nil for empty identifiers array' do
      result = subject.find_identifier_value([], 'Tracking Number')
      expect(result).to be_nil
    end

    it 'handles identifiers without value' do
      identifiers_without_value = [{ 'type' => { 'text' => 'Tracking Number' } }]
      result = subject.find_identifier_value(identifiers_without_value, 'Tracking Number')
      expect(result).to be_nil
    end
  end

  describe '#extract_codeable_concept_display' do
    context 'when codeable_concept is nil' do
      it 'returns nil' do
        expect(subject.extract_codeable_concept_display(nil)).to be_nil
      end
    end

    context 'with default prefer: :text' do
      it 'returns text when both text and coding display are present' do
        concept = { 'text' => 'Free text', 'coding' => [{ 'display' => 'Coded display' }] }
        expect(subject.extract_codeable_concept_display(concept)).to eq('Free text')
      end

      it 'falls back to coding display when text is absent' do
        concept = { 'coding' => [{ 'display' => 'Coded display' }] }
        expect(subject.extract_codeable_concept_display(concept)).to eq('Coded display')
      end

      it 'falls back to coding display when text is blank' do
        concept = { 'text' => '', 'coding' => [{ 'display' => 'Coded display' }] }
        expect(subject.extract_codeable_concept_display(concept)).to eq('Coded display')
      end

      it 'returns nil when both text and coding display are missing' do
        concept = { 'coding' => [{ 'code' => '12345' }] }
        expect(subject.extract_codeable_concept_display(concept)).to be_nil
      end

      it 'returns nil for empty hash' do
        expect(subject.extract_codeable_concept_display({})).to be_nil
      end

      it 'skips codings without display and returns one that has it' do
        concept = { 'coding' => [{ 'code' => 'A' }, { 'display' => 'Second' }] }
        expect(subject.extract_codeable_concept_display(concept)).to eq('Second')
      end
    end

    context 'with prefer: :coding' do
      it 'returns coding display when both text and coding display are present' do
        concept = { 'text' => 'Free text', 'coding' => [{ 'display' => 'Coded display' }] }
        expect(subject.extract_codeable_concept_display(concept, prefer: :coding)).to eq('Coded display')
      end

      it 'falls back to text when coding display is absent' do
        concept = { 'text' => 'Free text', 'coding' => [{ 'code' => '12345' }] }
        expect(subject.extract_codeable_concept_display(concept, prefer: :coding)).to eq('Free text')
      end

      it 'falls back to text when coding is nil' do
        concept = { 'text' => 'Free text' }
        expect(subject.extract_codeable_concept_display(concept, prefer: :coding)).to eq('Free text')
      end

      it 'returns nil when both are missing' do
        concept = { 'coding' => [{ 'code' => '12345' }] }
        expect(subject.extract_codeable_concept_display(concept, prefer: :coding)).to be_nil
      end
    end

    context 'when prefer is passed as a string' do
      it 'converts string to symbol and behaves like prefer: :coding' do
        concept = { 'text' => 'Free text', 'coding' => [{ 'display' => 'Coded display' }] }
        expect(subject.extract_codeable_concept_display(concept, prefer: 'coding')).to eq('Coded display')
      end

      it 'converts string to symbol and behaves like prefer: :text' do
        concept = { 'text' => 'Free text', 'coding' => [{ 'display' => 'Coded display' }] }
        expect(subject.extract_codeable_concept_display(concept, prefer: 'text')).to eq('Free text')
      end
    end
  end

  describe '#first_coding_display' do
    it 'returns the first coding display' do
      concept = { 'coding' => [{ 'display' => 'First' }, { 'display' => 'Second' }] }
      expect(subject.first_coding_display(concept)).to eq('First')
    end

    it 'skips codings without display' do
      concept = { 'coding' => [{ 'code' => 'A' }, { 'display' => 'Found' }] }
      expect(subject.first_coding_display(concept)).to eq('Found')
    end

    it 'returns nil when no coding has display' do
      concept = { 'coding' => [{ 'code' => 'A' }] }
      expect(subject.first_coding_display(concept)).to be_nil
    end

    it 'returns nil when coding is nil' do
      expect(subject.first_coding_display({})).to be_nil
    end

    it 'returns nil when coding is empty' do
      expect(subject.first_coding_display({ 'coding' => [] })).to be_nil
    end
  end
end
