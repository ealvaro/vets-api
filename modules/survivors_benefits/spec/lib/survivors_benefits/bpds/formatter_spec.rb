# frozen_string_literal: true

require 'rails_helper'
require 'survivors_benefits/bpds/formatter'

RSpec.describe SurvivorsBenefits::BPDS::Formatter do
  let(:parsed_form) do
    {
      'veteranFullName' => { 'first' => 'John', 'last' => 'Doe' },
      'veteranSocialSecurityNumber' => '333224444',
      'claimantFullName' => { 'first' => 'Derrick', 'last' => 'Stewart' }
    }
  end

  describe '#format' do
    context 'without attachments' do
      it 'returns the parsed form without an attachments key' do
        result = described_class.new(parsed_form).format

        expect(result).to eq(parsed_form)
        expect(result).not_to have_key('attachments')
      end
    end

    context 'with attachments in parsed_form[files]' do
      let(:files) do
        [
          { 'confirmationCode' => 'abc-1', 'name' => 'doc1.pdf', 'size' => 1234, 'type' => 'application/pdf' },
          { 'confirmationCode' => 'abc-2', 'name' => 'doc2.pdf', 'size' => 5678, 'type' => 'application/pdf' }
        ]
      end
      let(:form_with_files) { parsed_form.merge('files' => files) }

      it 'surfaces attachment metadata as an indexed list' do
        result = described_class.new(form_with_files).format

        expect(result['attachments']).to eq(
          [
            { 'index' => 1, 'confirmationCode' => 'abc-1', 'name' => 'doc1.pdf', 'size' => 1234,
              'type' => 'application/pdf' },
            { 'index' => 2, 'confirmationCode' => 'abc-2', 'name' => 'doc2.pdf', 'size' => 5678,
              'type' => 'application/pdf' }
          ]
        )
      end

      it 'preserves all original form fields' do
        result = described_class.new(form_with_files).format

        parsed_form.each do |key, value|
          expect(result[key]).to eq(value)
        end
      end

      it 'omits nil fields from each attachment entry' do
        result = described_class.new({ 'files' => [{ 'confirmationCode' => 'only' }] }).format

        expect(result['attachments']).to eq([{ 'index' => 1, 'confirmationCode' => 'only' }])
      end
    end

    context 'with empty files array' do
      it 'omits the attachments key' do
        result = described_class.new(parsed_form.merge('files' => [])).format

        expect(result).not_to have_key('attachments')
      end
    end

    context 'when parsed_form is nil' do
      it 'returns an empty hash' do
        expect(described_class.new(nil).format).to eq({})
      end
    end
  end
end
