# frozen_string_literal: true

require 'rails_helper'
require 'cave/change_log'

RSpec.describe Cave::ChangeLog do
  def submission(ocr)
    instance_double(CaveSubmission, parsed_response: ocr)
  end

  subject(:change_log) { described_class.new(cave_submissions: [submission(dd214_ocr)], form_data:) }

  let(:dd214_ocr) do
    {
      'VETERAN_NAME' => 'JON A DOE',
      'VETERAN_SSN' => '123456789',
      'BRANCH_OF_SERVICE' => 'ARMY USAR',
      'PAY_GRADE' => 'E-5',
      'DATE_SEPARATED_FROM_SERVICE' => '04/01/1982'
    }
  end

  # User-final, normalized values: name and pay grade corrected; branch/ssn/date unchanged.
  let(:dd214_user) do
    {
      'veteranName' => { 'first' => 'John', 'middle' => 'A', 'last' => 'Doe' },
      'veteranSsn' => '123456789',
      'branchOfService' => 'army',
      'payGrade' => 'E-6',
      'dateSeparatedFromService' => '1982-04-01'
    }
  end

  let(:form_data) do
    { 'files' => [{ 'idpArtifacts' => { 'dd214' => [dd214_user], 'deathCertificates' => [] } }] }
  end

  describe '#records' do
    it 'reports only the fields the user actually changed' do
      labels = change_log.records.map(&:label)
      expect(labels).to contain_exactly('Veteran name', 'Pay grade')
    end

    it 'captures the raw OCR value and the readable user value' do
      name = change_log.records.find { |r| r.label == 'Veteran name' }
      expect(name.ocr_value).to eq('JON A DOE')
      expect(name.user_value).to eq('John A Doe')
    end
  end

  describe '#remarks' do
    it 'emits the system-generated header, document grouping, and per-change lines' do
      expect(change_log.remarks).to eq(<<~REMARKS.strip)
        SYSTEM GENERATED TO DOCUMENT USER CHANGES
        DD-214
        Veteran name: OCR Extracted Value: JON A DOE; User Updated Value: John A Doe;
        Pay grade: OCR Extracted Value: E-5; User Updated Value: E-6;
      REMARKS
    end

    context 'when nothing changed' do
      let(:dd214_user) do
        {
          'veteranName' => { 'first' => 'Jon', 'middle' => 'A', 'last' => 'Doe' },
          'veteranSsn' => '123456789',
          'branchOfService' => 'army',
          'payGrade' => 'E-5',
          'dateSeparatedFromService' => '1982-04-01'
        }
      end

      it 'returns a non-empty fallback line so the 21-4138 schema stays satisfied' do
        expect(change_log.records).to be_empty
        expect(change_log.remarks).to eq(
          "SYSTEM GENERATED TO DOCUMENT USER CHANGES\nNo user changes were made to the extracted document data."
        )
      end
    end

    context 'with no cave submissions' do
      subject(:change_log) { described_class.new(cave_submissions: [], form_data:) }

      it 'reports no records and emits the non-empty fallback line' do
        expect(change_log.records).to be_empty
        expect(change_log.remarks).to eq(
          "SYSTEM GENERATED TO DOCUMENT USER CHANGES\nNo user changes were made to the extracted document data."
        )
      end
    end

    context 'with both a DD-214 and a Death Certificate' do
      subject(:change_log) do
        described_class.new(cave_submissions: [submission(dd214_ocr), submission(death_ocr)], form_data:)
      end

      let(:death_ocr) do
        { 'DECENDENT_FULL_NAME' => 'JANE DOE', 'CAUSE_OF_DEATH' => 'Cardiac arrest' }
      end
      let(:death_user) do
        { 'decendentFullName' => { 'first' => 'Jane', 'last' => 'Doe' }, 'causeOfDeath' => 'Heart failure' }
      end
      let(:form_data) do
        {
          'files' => [
            { 'idpArtifacts' => { 'dd214' => [dd214_user], 'deathCertificates' => [death_user] } }
          ]
        }
      end

      it 'groups changes under each document name' do
        remarks = change_log.remarks
        expect(remarks).to include("DD-214\n")
        expect(remarks).to include("Death Certificate\n")
        expect(remarks).to include('Cause of death: OCR Extracted Value: Cardiac arrest; ' \
                                   'User Updated Value: Heart failure;')
      end
    end
  end

  describe '#records_for' do
    it 'returns the changed-field records scoped to a single submission' do
      sub = submission(dd214_ocr)
      log = described_class.new(cave_submissions: [sub], form_data:)
      expect(log.records_for(sub).map(&:label)).to contain_exactly('Veteran name', 'Pay grade')
    end
  end
end
