# frozen_string_literal: true

require 'rails_helper'
require 'pdf/reader'

RSpec.describe SimpleFormsApi::OverflowPdfGenerator do
  let(:cutoff) { 3685 }

  def pdf_text(path)
    PDF::Reader.new(path).pages.map(&:text).join("\n")
  end

  before { @generated_paths = [] }

  after do
    @generated_paths.each { |p| FileUtils.rm_f(p) if p.present? && File.exist?(p) }
  end

  describe '#generate' do
    context 'when the veteran is filing for themselves' do
      let(:data) do
        {
          'statement' => "#{'a' * 3686} overflow content",
          'claimant_type' => 'self',
          'first' => 'John', 'middle' => 'M', 'last' => 'Doe',
          'id_number' => { 'ssn' => '123456789' }
        }
      end

      it 'returns a path to an existing PDF file' do
        path = described_class.new(data, cutoff:).generate
        @generated_paths << path
        expect(path).to be_a(String)
        expect(File.exist?(path)).to be(true)
      end

      it 'renders the veteran name, SSN, header, and overflow text' do
        path = described_class.new(data, cutoff:).generate
        @generated_paths << path
        content = pdf_text(path)

        aggregate_failures do
          expect(content).to match(/VA\s*Form\s*21-4138/i)
          expect(content).to match(/Name:\s*John\s*M\s*Doe/i)
          expect(content).to match(/SSN:\s*123-45-6789/)
          expect(content).to match(/Remarks.*continued/i)
          expect(content).to match(/overflow\s*content/i)
        end
      end
    end

    context 'when the veteran is filing and veteran_full_name is also present' do
      let(:data) do
        {
          'statement' => "#{'a' * 3686} overflow content",
          'claimant_type' => 'self',
          'first' => 'John', 'middle' => 'M', 'last' => 'Doe',
          'id_number' => { 'ssn' => '123456789' },
          # should be ignored for self-filers
          'veteran_full_name' => { 'first' => 'Other', 'last' => 'Person' },
          'veteran_id_number' => { 'ssn' => '000000000' }
        }
      end

      it 'uses the top-level profile name, not veteran_full_name' do
        path = described_class.new(data, cutoff:).generate
        @generated_paths << path
        content = pdf_text(path)

        aggregate_failures do
          expect(content).to match(/Name:\s*John\s*M\s*Doe/i)
          expect(content).not_to match(/Other\s*Person/i)
          expect(content).to match(/SSN:\s*123-45-6789/)
          expect(content).not_to match(/SSN:\s*000-00-0000/)
        end
      end
    end

    context 'when a non-veteran is filing on behalf of a veteran' do
      let(:data) do
        {
          'statement' => "#{'a' * 3686} overflow content",
          'claimant_type' => 'forVeteran',
          'full_name' => { 'first' => 'Filling', 'last' => 'ForVeteran' },
          'id_number' => { 'ssn' => '000000000' },
          'veteran_full_name' => { 'first' => 'Bobby', 'last' => 'Buchemi' },
          'veteran_id_number' => { 'ssn' => '987341231' }
        }
      end

      it 'uses the veteran name, not the claimant name' do
        path = described_class.new(data, cutoff:).generate
        @generated_paths << path
        content = pdf_text(path)

        aggregate_failures do
          expect(content).to match(/Name:\s*Bobby\s*Buchemi/i)
          expect(content).not_to match(/Filling\s*ForVeteran/i)
        end
      end

      it 'uses the veteran SSN, not the claimant SSN' do
        path = described_class.new(data, cutoff:).generate
        @generated_paths << path
        content = pdf_text(path)

        aggregate_failures do
          expect(content).to match(/SSN:\s*987-34-1231/)
          expect(content).not_to match(/SSN:\s*000-00-0000/)
        end
      end
    end

    context 'when a non-veteran is filing and the veteran has a VA file number' do
      let(:data) do
        {
          'statement' => ('b' * 3687),
          'claimant_type' => 'forVeteran',
          'veteran_full_name' => { 'first' => 'Bobby', 'last' => 'Buchemi' },
          'veteran_id_number' => { 'va_file_number' => '12345678', 'ssn' => '987341231' }
        }
      end

      it 'prefers VA file number over SSN' do
        path = described_class.new(data, cutoff:).generate
        @generated_paths << path
        content = pdf_text(path)

        aggregate_failures do
          expect(content).to match(/VA\s*File\s*Number:\s*12345678/i)
          expect(content).not_to match(/SSN:\s*987-34-1231/)
        end
      end
    end

    context 'when the veteran is filing and VA file number is present' do
      let(:data) do
        {
          'statement' => ('b' * 3687),
          'claimant_type' => 'self',
          'first' => 'Jane', 'last' => 'Veteran',
          'id_number' => { 'va_file_number' => '88888888', 'ssn' => '987654321' }
        }
      end

      it 'prefers VA file number over SSN' do
        path = described_class.new(data, cutoff:).generate
        @generated_paths << path
        content = pdf_text(path)

        aggregate_failures do
          expect(content).to match(/VA\s*File\s*Number:\s*88888888/i)
          expect(content).not_to match(/SSN:\s*987-65-4321/)
        end
      end
    end

    context 'when no name is provided' do
      let(:data) do
        {
          'statement' => ('c' * 3687),
          'claimant_type' => 'self',
          'id_number' => { 'ssn' => '123456789' }
        }
      end

      it 'renders Name: Not provided' do
        path = described_class.new(data, cutoff:).generate
        @generated_paths << path
        content = pdf_text(path)

        expect(content).to match(/Name:\s*Not\s*provided/i)
      end
    end

    context 'when there is no overflow text' do
      let(:data) do
        {
          'statement' => 'a' * 3685,
          'claimant_type' => 'self',
          'first' => 'John', 'last' => 'Doe',
          'id_number' => { 'ssn' => '123456789' }
        }
      end

      it 'returns nil' do
        path = described_class.new(data, cutoff:).generate
        expect(path).to be_nil
      end
    end
  end
end
