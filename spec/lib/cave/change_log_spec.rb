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

  # Conflict-resolution fields (name, SSN, DOB, branch, service dates) are corrected on the
  # top-level 534EZ/8416 form, not the artifact editor, so their idpArtifacts entry keeps the
  # raw CAVE extraction. The change log must diff OCR against the top-level form value for
  # these — otherwise those corrections never reach the 21-4138 (issue #147162).
  describe 'conflict-resolution fields corrected on the top-level form' do
    let(:dd214_ocr) do
      { 'VETERAN_NAME' => 'JEFERY J HAYES', 'VETERAN_DOB' => '01/01/1950' }
    end

    # idpArtifacts still holds the raw OCR values (the frontend never wrote the correction here).
    let(:stale_artifact) do
      { 'veteranName' => { 'first' => 'Jefery', 'middle' => 'J', 'last' => 'Hayes' }, 'veteranDob' => '1950-01-01' }
    end

    let(:form_data) do
      {
        'veteranFullName' => { 'first' => 'Jeffery', 'middle' => 'John', 'last' => 'Hayes' },
        'veteranDateOfBirth' => '1950-06-15',
        'files' => [{ 'idpArtifacts' => { 'dd214' => [stale_artifact], 'deathCertificates' => [] } }]
      }
    end

    it 'records corrections made on the top-level form even though idpArtifacts is stale' do
      records = change_log.records.index_by(&:label)
      expect(records.keys).to contain_exactly('Veteran name', 'Date of birth')
      expect(records['Veteran name'].ocr_value).to eq('JEFERY J HAYES')
      expect(records['Veteran name'].user_value).to eq('Jeffery John Hayes')
      expect(records['Date of birth'].user_value).to eq('06/15/1950')
    end

    context 'when the top-level form value is absent (e.g. death-certificate-only flow)' do
      let(:form_data) do
        { 'files' => [{ 'idpArtifacts' => { 'dd214' => [stale_artifact], 'deathCertificates' => [] } }] }
      end

      it 'falls back to the idpArtifacts value and reports no spurious OCR -> (none) change' do
        expect(change_log.records).to be_empty
      end
    end

    context 'branch of service corrected on the top-level form' do
      let(:dd214_ocr) { { 'BRANCH_OF_SERVICE' => 'ARMY USAR' } }

      # idpArtifacts keeps the OCR-derived 534 enum ('army'); the correction ('navy')
      # lands only on the top-level serviceBranch field.
      let(:form_data) do
        {
          'serviceBranch' => 'navy',
          'files' => [{ 'idpArtifacts' => { 'dd214' => [{ 'branchOfService' => 'army' }],
                                            'deathCertificates' => [] } }]
        }
      end

      it 'diffs OCR against the corrected top-level branch and renders its label' do
        records = change_log.records.index_by(&:label)
        expect(records.keys).to contain_exactly('Branch of service')
        expect(records['Branch of service'].ocr_value).to eq('ARMY USAR')
        expect(records['Branch of service'].user_value).to eq('Navy')
      end
    end

    context 'SSN corrected on the top-level form (post-splitVaSsnField bare string)' do
      let(:dd214_ocr) { { 'VETERAN_SSN' => '123-45-6789' } }

      # At submit, veteranSocialSecurityNumber is flattened from { ssn: ... } to a bare
      # 9-digit string (see splitSsn.js); idpArtifacts still holds the raw OCR SSN.
      let(:form_data) do
        {
          'veteranSocialSecurityNumber' => '987654321',
          'files' => [{ 'idpArtifacts' => { 'dd214' => [{ 'veteranSsn' => '123456789' }],
                                            'deathCertificates' => [] } }]
        }
      end

      it 'diffs OCR against the bare-string top-level SSN and formats it' do
        records = change_log.records.index_by(&:label)
        expect(records.keys).to contain_exactly('Social Security number')
        expect(records['Social Security number'].ocr_value).to eq('123-45-6789')
        expect(records['Social Security number'].user_value).to eq('987-65-4321')
      end
    end

    context 'service dates corrected on the top-level form (nested activeServiceDateRange path)' do
      let(:dd214_ocr) do
        { 'DATE_ENTERED_ACTIVE_SERVICE' => '06/22/2000', 'DATE_SEPARATED_FROM_SERVICE' => '06/30/2004' }
      end

      # idpArtifacts still holds the raw OCR-equivalent ISO dates.
      let(:stale_dd214) do
        { 'dateEnteredActiveService' => '2000-06-22', 'dateSeparatedFromService' => '2004-06-30' }
      end

      context 'when both endpoints are corrected' do
        let(:form_data) do
          {
            'activeServiceDateRange' => { 'from' => '2000-07-01', 'to' => '2004-12-31' },
            'files' => [{ 'idpArtifacts' => { 'dd214' => [stale_dd214], 'deathCertificates' => [] } }]
          }
        end

        it 'walks the two-key form_path and records both corrections' do
          records = change_log.records.index_by(&:label)
          expect(records.keys).to contain_exactly('Date entered active service', 'Date separated from service')
          expect(records['Date entered active service'].user_value).to eq('07/01/2000')
          expect(records['Date separated from service'].user_value).to eq('12/31/2004')
        end
      end

      context 'when only the start date is present on the form' do
        let(:form_data) do
          {
            'activeServiceDateRange' => { 'from' => '2000-07-01' },
            'files' => [{ 'idpArtifacts' => { 'dd214' => [stale_dd214], 'deathCertificates' => [] } }]
          }
        end

        it 'records the corrected start and falls back to idpArtifacts for the absent end' do
          records = change_log.records.index_by(&:label)
          expect(records.keys).to contain_exactly('Date entered active service')
          expect(records['Date entered active service'].user_value).to eq('07/01/2000')
        end
      end
    end

    context 'when the top-level form value matches the OCR value' do
      let(:dd214_ocr) do
        { 'VETERAN_NAME' => 'JON A DOE', 'VETERAN_SSN' => '123-45-6789' }
      end

      # The correction equals the extracted value (merely reshaped), so nothing changed.
      let(:form_data) do
        {
          'veteranFullName' => { 'first' => 'Jon', 'middle' => 'A', 'last' => 'Doe' },
          'veteranSocialSecurityNumber' => '123456789',
          'files' => [{ 'idpArtifacts' => { 'dd214' => [{}], 'deathCertificates' => [] } }]
        }
      end

      it 'reports no change' do
        expect(change_log.records).to be_empty
      end
    end
  end

  # The death certificate's DECENDENT_* fields resolve to the veteran-level top-level form
  # fields (the decedent is the veteran on a survivors-benefits claim).
  describe 'death-certificate conflict fields corrected on the top-level form' do
    subject(:change_log) { described_class.new(cave_submissions: [submission(death_ocr)], form_data:) }

    let(:death_ocr) do
      {
        'DECENDENT_FULL_NAME' => 'JANE A DOE',
        'DECENDENT_SSN' => '111-22-3333',
        'DECENDENT_DATE_OF_DEATH' => '03/15/2023'
      }
    end

    # idpArtifacts keeps the raw CAVE extraction for the decedent conflict fields.
    let(:stale_death) do
      {
        'decendentFullName' => { 'first' => 'Jane', 'middle' => 'A', 'last' => 'Doe' },
        'decendentSsn' => '111223333',
        'decendentDateOfDeath' => '2023-03-15'
      }
    end

    let(:form_data) do
      {
        'veteranFullName' => { 'first' => 'Janet', 'middle' => 'Anne', 'last' => 'Doe' },
        'veteranSocialSecurityNumber' => '444556666',
        'veteranDateOfDeath' => '2023-04-01',
        'files' => [{ 'idpArtifacts' => { 'dd214' => [], 'deathCertificates' => [stale_death] } }]
      }
    end

    it 'diffs the DECENDENT_* OCR against the veteran-level top-level form fields' do
      records = change_log.records.index_by(&:label)
      expect(records.keys).to contain_exactly('Decedent name', 'Social Security number', 'Date of death')
      expect(records['Decedent name'].user_value).to eq('Janet Anne Doe')
      expect(records['Social Security number'].user_value).to eq('444-55-6666')
      expect(records['Date of death'].user_value).to eq('04/01/2023')
    end

    context 'when the top-level form values are absent' do
      let(:form_data) do
        { 'files' => [{ 'idpArtifacts' => { 'dd214' => [], 'deathCertificates' => [stale_death] } }] }
      end

      it 'falls back to idpArtifacts and reports no spurious change' do
        expect(change_log.records).to be_empty
      end
    end
  end
end
