# frozen_string_literal: true

require 'rails_helper'
require 'pdf/reader'

RSpec.describe SimpleFormsApi::Overflow4502 do
  def pdf_text(path)
    PDF::Reader.new(path).pages.map(&:text).join("\n")
  end
  before { @generated_paths = [] }

  after do
    @generated_paths.each { |p| FileUtils.rm_f(p) if p.present? && File.exist?(p) }
  end

  describe '#generate' do
    let(:data) { {} }

    it 'add nothing to page if nothing is provided' do
      path = described_class.new(data).generate
      @generated_paths << path
      content = pdf_text(path)
      expect(content).not_to include('email')
      expect(content).not_to include('drive')
      expect(content).not_to include('passenger')
    end

    it 'adds email if provided' do
      data['email'] = 'example.email.12345@example.com'
      path = described_class.new(data).generate
      @generated_paths << path
      content = pdf_text(path)
      expect(content).to include('EMAILADDRESS')
      expect(content).to include('example.email.12345@example.com')
      expect(content).not_to include('drive')
      expect(content).not_to include('passenger')
    end

    it 'adds driver info if provided' do
      data['veteran_will_operate_vehicle'] = true
      path = described_class.new(data).generate
      @generated_paths << path
      content = pdf_text(path)
      expect(content).not_to include('EMAILADDRESS')
      expect(content).not_to include('example.email.12345@example.com')
      expect(content).to include('True, veteranmaydrive')
      expect(content).not_to include('passenger')
    end

    it 'adds passanger info if provided' do
      data['veteran_will_operate_vehicle'] = false
      path = described_class.new(data).generate
      @generated_paths << path
      content = pdf_text(path)
      expect(content).not_to include('EMAILADDRESS')
      expect(content).not_to include('example.email.12345@example.com')
      expect(content).to include('False, Iamapassengeronly')
      expect(content).not_to include('drive')
    end
  end
end
