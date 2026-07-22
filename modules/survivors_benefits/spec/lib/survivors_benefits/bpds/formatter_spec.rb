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

  # The field-by-field structured data mapping is exercised by the StructuredData
  # service specs; here we stub it so the Formatter's own contract (#format returns the
  # structured data, #attachments returns the document list) is tested in isolation.
  let(:structured_data) { { 'VETERAN_NAME' => 'John Doe', 'VETERAN_SSN_1' => '333224444' } }
  let(:v2022_service) do
    instance_double(SurvivorsBenefits::StructuredData::V2022::StructuredDataService,
                    build_structured_data: structured_data)
  end
  let(:v2025_service) do
    instance_double(SurvivorsBenefits::StructuredData::V2025::StructuredDataService,
                    build_structured_data: structured_data)
  end

  before do
    allow(SurvivorsBenefits::StructuredData::V2022::StructuredDataService).to receive(:new).and_return(v2022_service)
    allow(SurvivorsBenefits::StructuredData::V2025::StructuredDataService).to receive(:new).and_return(v2025_service)
    allow(Flipper).to receive(:enabled?).and_call_original
    allow(Flipper).to receive(:enabled?).with(:survivors_benefits_form_2025_version_enabled).and_return(false)
  end

  describe '#format' do
    it 'returns the generated structured data' do
      expect(described_class.new(parsed_form).format).to eq(structured_data)
    end

    it 'never includes an attachments key (attachments live in the BPDS envelope, not the payload)' do
      expect(described_class.new(parsed_form.merge('files' => [{ 'confirmationCode' => 'x' }])).format)
        .not_to have_key('attachments')
    end

    context 'when parsed_form is nil' do
      it 'still builds the structured data payload' do
        result = described_class.new(nil).format

        expect(SurvivorsBenefits::StructuredData::V2022::StructuredDataService).to have_received(:new).with({})
        expect(result).to eq(structured_data)
      end
    end

    describe 'form version selection' do
      it 'uses the V2022 service when the 2025 flag is off' do
        described_class.new(parsed_form).format

        expect(SurvivorsBenefits::StructuredData::V2022::StructuredDataService).to have_received(:new).with(parsed_form)
        expect(SurvivorsBenefits::StructuredData::V2025::StructuredDataService).not_to have_received(:new)
      end

      it 'uses the V2025 service when the 2025 flag is on' do
        allow(Flipper).to receive(:enabled?).with(:survivors_benefits_form_2025_version_enabled).and_return(true)

        described_class.new(parsed_form).format

        expect(SurvivorsBenefits::StructuredData::V2025::StructuredDataService).to have_received(:new).with(parsed_form)
        expect(SurvivorsBenefits::StructuredData::V2022::StructuredDataService).not_to have_received(:new)
      end
    end
  end

  describe '#attachments' do
    let(:dd214_file) do
      {
        'confirmationCode' => 'dd214-code',
        'name' => 'dd214.pdf',
        'size' => 1024,
        'type' => 'application/pdf',
        'idpArtifacts' => {
          'dd214' => [
            {
              'veteranName' => { 'first' => 'John', 'last' => 'Doe' },
              'veteranSsn' => '987654321',
              'branchOfService' => 'ARMY'
            }
          ]
        }
      }
    end
    let(:plain_file) do
      { 'confirmationCode' => 'plain-code', 'name' => 'other.pdf', 'size' => 22, 'type' => 'application/pdf' }
    end

    it 'returns nil when there are no files' do
      expect(described_class.new(parsed_form).attachments).to be_nil
    end

    it 'returns nil when files is an empty array' do
      expect(described_class.new(parsed_form.merge('files' => [])).attachments).to be_nil
    end

    it 'surfaces upload metadata as an indexed list, dropping nil fields' do
      result = described_class.new({ 'files' => [{ 'confirmationCode' => 'only' }] }).attachments

      expect(result).to eq([{ 'index' => 1, 'confirmationCode' => 'only' }])
    end

    it 'combines upload metadata with the CAVE-extracted structured data' do
      attachment = described_class.new(parsed_form.merge('files' => [dd214_file])).attachments.first

      expect(attachment).to include(
        'index' => 1,
        'confirmationCode' => 'dd214-code',
        'name' => 'dd214.pdf',
        'size' => 1024,
        'type' => 'application/pdf'
      )
      expect(attachment['structuredData']).to include(
        'VETERAN_NAME' => 'John Doe',
        'VETERAN_SSN' => '987654321',
        'BRANCH_OF_SERVICE' => 'ARMY'
      )
    end

    it 'represents missing structured data values as empty strings, not nil' do
      structured = described_class.new(parsed_form.merge('files' => [dd214_file])).attachments.first['structuredData']

      expect(structured.values).not_to include(nil)
      # dd214_file only carries name/ssn/branch, so the unmapped fields normalize to ''
      expect(structured).to include('PAY_GRADE' => '', 'VETERAN_DOB' => '', 'SEPARATION_CODE' => '')
    end

    it 'omits structuredData for files without CAVE idpArtifacts' do
      result = described_class.new(parsed_form.merge('files' => [plain_file])).attachments

      expect(result).to eq(
        [{ 'index' => 1, 'confirmationCode' => 'plain-code', 'name' => 'other.pdf', 'size' => 22,
           'type' => 'application/pdf' }]
      )
    end

    it 'indexes each attachment and only enriches the CAVE-validated file' do
      result = described_class.new(parsed_form.merge('files' => [plain_file, dd214_file])).attachments

      expect(result.map { |a| a['index'] }).to eq([1, 2])
      expect(result[0]).not_to have_key('structuredData')
      expect(result[1]).to have_key('structuredData')
    end
  end
end
