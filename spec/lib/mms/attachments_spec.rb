# frozen_string_literal: true

require 'rails_helper'
require 'mms/data_formatting'
require 'mms/attachments'

RSpec.describe Mms::Attachments do
  let(:unknown_file) do
    { idpArtifacts: { unknown: [{ decendentFullName: { first: 'Jane', last: 'Smith' } }] } }
  end

  let(:form_files) do
    [
      {
        confirmationCode: '12345',
        name: 'test_file.pdf',
        size: 1024,
        isEncrypted: false,
        type: 'application/pdf',
        lastModified: '2024-06-01T12:00:00Z',
        idpTrackingKey: 'tracking_key',
        idpUploadStatus: 'uploaded',
        idpDocumentId: 'doc_id',
        idpBucket: 'bucket',
        idpPdfKey: 'pdf_key',
        idpArtifacts: {
          dd214: [
            {
              veteranName: {
                first: 'John',
                last: 'Doe'
              },
              veteranSsn: '987654321',
              veteranDob: '1990-01-01',
              branchOfService: 'branch',
              gradeRateRank: 'grade rate rank',
              payGrade: 'pay grade',
              dateInducted: '2024-01-01',
              dateEnteredActiveService: '2024-01-02',
              dateSeparatedFromService: '2024-01-03',
              causeOfSeparation: 'cause of separation',
              characterOfService: 'character of service',
              separationType: 'separation type',
              separationCode: 'separation code'
            }
          ]
        }
      },
      {
        confirmationCode: '67890',
        name: 'another_test_file.pdf',
        size: 2048,
        isEncrypted: true,
        type: 'application/pdf',
        lastModified: '2024-06-02T12:00:00Z',
        idpTrackingKey: 'another_tracking_key',
        idpUploadStatus: 'uploaded',
        idpDocumentId: 'another_doc_id',
        idpBucket: 'another_bucket',
        idpPdfKey: 'another_pdf_key',
        idpArtifacts: {
          deathCertificates: [
            {
              decendentFullName: {
                first: 'Jane',
                last: 'Smith'
              },
              decendentSsn: '123456789',
              decendentDateOfDeath: '2024-05-01',
              decendentDateOfDisposition: '2024-05-02',
              causeOfDeath: 'cause A',
              underlyingCauseOfDeathB: 'cause B',
              underlyingCauseOfDeathC: 'cause C',
              underlyingCauseOfDeathD: 'cause D',
              mannerOfDeath: 'manner',
              decendentMaritalStatus: 'married'
            }
          ]
        }
      }
    ]
  end
  let(:dd214_attrs) { form_files.first.dig(:idpArtifacts, :dd214).first }
  let(:death_cert_attrs) { form_files.last.dig(:idpArtifacts, :deathCertificates).first }

  describe Mms::Attachments::Service do
    it 'includes the AttachedFile struct' do
      expect(Mms::Attachments::Service::AttachedFile.members).to include(
        :confirmation_code,
        :name,
        :attachment_size,
        :is_encrypted,
        :attachment_type,
        :last_modified,
        :idp_tracking_key,
        :idp_upload_status,
        :idp_document_id,
        :idp_bucket,
        :idp_pdf_key,
        :form_data
      )
    end

    describe '#initialize' do
      it 'instantiates the files hash' do
        service = Mms::Attachments::Service.new(form_files)
        expect(service.files).to be_a(Hash)
      end

      it 'calls #parse_files' do
        allow_any_instance_of(Mms::Attachments::Service).to receive(:parse_files).and_call_original
        service = Mms::Attachments::Service.new(form_files)
        expect(service).to have_received(:parse_files)
      end
    end

    describe '#parse_files' do
      it 'correctly parses the form files into the files hash' do
        service = Mms::Attachments::Service.new(form_files)
        expect(service.files).to have_key(:dd214)
        expect(service.files[:dd214].confirmation_code).to eq('12345')
        expect(service.files).to have_key(:deathCertificates)
        expect(service.files[:deathCertificates].confirmation_code).to eq('67890')
      end
    end

    describe '#determine_form_type' do
      it 'returns the correct form type for dd214' do
        service = Mms::Attachments::Service.new(form_files)
        expect(
          service.send(:determine_form_type, form_files.first)
        ).to eq({ key: :dd214, klass: Mms::Attachments::Dd214 })
      end

      it 'returns the correct form type for deathCertificates' do
        service = Mms::Attachments::Service.new(form_files)
        expect(
          service.send(:determine_form_type, form_files.last)
        ).to eq({ key: :deathCertificates, klass: Mms::Attachments::DeathCertificate })
      end

      it 'returns nil for an unknown form type' do
        service = Mms::Attachments::Service.new(form_files)
        expect(service.send(:determine_form_type, unknown_file)).to eq(:unknown)
      end
    end

    describe '#get_form_object' do
      it 'returns the correct form object for dd214' do
        service = Mms::Attachments::Service.new(form_files)
        expect(
          service.send(:get_form_object, Mms::Attachments::Dd214, dd214_attrs)
        ).to be_a(Mms::Attachments::Dd214)
      end

      it 'returns the correct form object for deathCertificates' do
        service = Mms::Attachments::Service.new(form_files)
        expect(
          service.send(:get_form_object, Mms::Attachments::DeathCertificate, death_cert_attrs)
        ).to be_a(Mms::Attachments::DeathCertificate)
      end

      it 'returns nil for an unknown form object' do
        service = Mms::Attachments::Service.new(form_files)
        expect(service.send(:get_form_object, unknown_file, nil)).to be_nil
      end
    end
  end

  describe Mms::Attachments::DeathCertificate do
    describe '#initialize' do
      it 'sets the attributes correctly' do
        death_cert = Mms::Attachments::DeathCertificate.new(death_cert_attrs)
        expect(death_cert.attrs[:decendentFullName]).to eq(death_cert_attrs[:decendentFullName])
        expect(death_cert.attrs[:decendentSsn]).to eq(death_cert_attrs[:decendentSsn])
        expect(death_cert.attrs[:decendentDateOfDeath]).to eq(death_cert_attrs[:decendentDateOfDeath])
        expect(death_cert.attrs[:decendentDateOfDisposition]).to eq(death_cert_attrs[:decendentDateOfDisposition])
        expect(death_cert.attrs[:causeOfDeath]).to eq(death_cert_attrs[:causeOfDeath])
        expect(death_cert.attrs[:underlyingCauseOfDeathB]).to eq(death_cert_attrs[:underlyingCauseOfDeathB])
        expect(death_cert.attrs[:underlyingCauseOfDeathC]).to eq(death_cert_attrs[:underlyingCauseOfDeathC])
        expect(death_cert.attrs[:underlyingCauseOfDeathD]).to eq(death_cert_attrs[:underlyingCauseOfDeathD])
        expect(death_cert.attrs[:mannerOfDeath]).to eq(death_cert_attrs[:mannerOfDeath])
        expect(death_cert.attrs[:decendentMaritalStatus]).to eq(death_cert_attrs[:decendentMaritalStatus])
      end

      describe '#transform_data' do
        it 'transforms the data correctly' do
          death_cert = Mms::Attachments::DeathCertificate.new(death_cert_attrs)
          transformed = death_cert.transform_data
          expect(transformed['DECEDENT_FULL_NAME']).to eq(Mms::Attachments::DeathCertificate.new(death_cert_attrs).build_name(death_cert_attrs[:decendentFullName].transform_keys(&:to_s))[:full])
          expect(transformed['DECEDENT_SSN']).to eq(death_cert_attrs[:decendentSsn])
          expect(transformed['DECEDENT_DATE_OF_DEATH']).to eq(Mms::Attachments::DeathCertificate.new(death_cert_attrs).format_date(death_cert_attrs[:decendentDateOfDeath]))
          expect(transformed['DECEDENT_DATE_OF_DISPOSITION']).to eq(Mms::Attachments::DeathCertificate.new(death_cert_attrs).format_date(death_cert_attrs[:decendentDateOfDisposition]))
          expect(transformed['CAUSE_OF_DEATH']).to eq(death_cert_attrs[:causeOfDeath])
          expect(transformed['UNDERLYING_CAUSE_OF_DEATH_B']).to eq(death_cert_attrs[:underlyingCauseOfDeathB])
          expect(transformed['UNDERLYING_CAUSE_OF_DEATH_C']).to eq(death_cert_attrs[:underlyingCauseOfDeathC])
          expect(transformed['UNDERLYING_CAUSE_OF_DEATH_D']).to eq(death_cert_attrs[:underlyingCauseOfDeathD])
          expect(transformed['MANNER_OF_DEATH']).to eq(death_cert_attrs[:mannerOfDeath])
          expect(transformed['DECEDENT_MARITAL_STATUS']).to eq(death_cert_attrs[:decendentMaritalStatus])
        end
      end
    end
  end

  describe Mms::Attachments::Dd214 do
    it 'sets the attributes correctly' do
      dd214 = Mms::Attachments::Dd214.new(dd214_attrs)
      expect(dd214.attrs[:veteranName]).to eq(dd214_attrs[:veteranName])
      expect(dd214.attrs[:veteranSsn]).to eq(dd214_attrs[:veteranSsn])
      expect(dd214.attrs[:veteranDob]).to eq(dd214_attrs[:veteranDob])
      expect(dd214.attrs[:branchOfService]).to eq(dd214_attrs[:branchOfService])
      expect(dd214.attrs[:gradeRateRank]).to eq(dd214_attrs[:gradeRateRank])
      expect(dd214.attrs[:payGrade]).to eq(dd214_attrs[:payGrade])
      expect(dd214.attrs[:dateInducted]).to eq(dd214_attrs[:dateInducted])
      expect(dd214.attrs[:dateEnteredActiveService]).to eq(dd214_attrs[:dateEnteredActiveService])
      expect(dd214.attrs[:dateSeparatedFromService]).to eq(dd214_attrs[:dateSeparatedFromService])
      expect(dd214.attrs[:causeOfSeparation]).to eq(dd214_attrs[:causeOfSeparation])
      expect(dd214.attrs[:characterOfService]).to eq(dd214_attrs[:characterOfService])
      expect(dd214.attrs[:separationType]).to eq(dd214_attrs[:separationType])
      expect(dd214.attrs[:separationCode]).to eq(dd214_attrs[:separationCode])
    end

    describe '#transform_data' do
      it 'transforms the data correctly' do
        dd214 = Mms::Attachments::Dd214.new(dd214_attrs)
        transformed = dd214.transform_data
        expect(transformed['VETERAN_NAME']).to eq(Mms::Attachments::Dd214.new(dd214_attrs).build_name(dd214_attrs[:veteranName].transform_keys(&:to_s))[:full])
        expect(transformed['VETERAN_SSN']).to eq(dd214_attrs[:veteranSsn])
        expect(transformed['VETERAN_DOB']).to eq(Mms::Attachments::Dd214.new(dd214_attrs).format_date(dd214_attrs[:veteranDob]))
        expect(transformed['BRANCH_OF_SERVICE']).to eq(dd214_attrs[:branchOfService])
        expect(transformed['GRADE_RATE_RANK']).to eq(dd214_attrs[:gradeRateRank])
        expect(transformed['PAY_GRADE']).to eq(dd214_attrs[:payGrade])
        expect(transformed['DATE_INDUCTED']).to eq(Mms::Attachments::Dd214.new(dd214_attrs).format_date(dd214_attrs[:dateInducted]))
        expect(transformed['DATE_ENTERED_ACTIVE_SERVICE']).to eq(Mms::Attachments::Dd214.new(dd214_attrs).format_date(dd214_attrs[:dateEnteredActiveService]))
        expect(transformed['DATE_SEPARATED_ACTIVE_SERVICE']).to eq(Mms::Attachments::Dd214.new(dd214_attrs).format_date(dd214_attrs[:dateSeparatedFromService]))
        expect(transformed['CAUSE_OF_SEPARATION']).to eq(dd214_attrs[:causeOfSeparation])
        expect(transformed['CHARACTER_OF_SERVICE']).to eq(dd214_attrs[:characterOfService])
        expect(transformed['SEPARATION_TYPE']).to eq(dd214_attrs[:separationType])
        expect(transformed['SEPARATION_CODE']).to eq(dd214_attrs[:separationCode])
      end
    end
  end
end
