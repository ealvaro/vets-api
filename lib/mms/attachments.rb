# frozen_string_literal: true

module Mms
  module Attachments
    require 'mms/data_formatting'
    class Service
      AttachedFile = Struct.new(
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
      attr_accessor :files

      def initialize(form_files)
        @files = {}
        parse_files(form_files)
      end

      def parse_files(form_files)
        form_files.each do |file|
          file = file.deep_symbolize_keys
          form_type = determine_form_type(file)
          next if form_type == :unknown

          form_object = get_form_object(form_type[:klass], file.dig(:idpArtifacts, form_type[:key])&.first)
          next unless form_object

          attached_file = AttachedFile.new(file[:confirmationCode],
                                           file[:name],
                                           file[:size],
                                           file[:isEncrypted],
                                           file[:type],
                                           file[:lastModified],
                                           file[:idpTrackingKey],
                                           file[:idpUploadStatus],
                                           file[:idpDocumentId],
                                           file[:idpBucket],
                                           file[:idpPdfKey],
                                           form_object.transform_data)

          files[form_type[:key]] = attached_file
        end
      end

      def determine_form_type(file)
        if file.dig(:idpArtifacts, :dd214)&.any?
          { key: :dd214, klass: Dd214 }
        elsif file.dig(:idpArtifacts, :deathCertificates)&.any?
          { key: :deathCertificates, klass: DeathCertificate }
        else
          :unknown
        end
      end

      def get_form_object(klass, form_attributes)
        return nil unless form_attributes

        klass.new(form_attributes)
      end
    end

    class DeathCertificate
      include Mms::DataFormatting
      attr_reader :attrs

      def initialize(attributes)
        @attrs = attributes
      end

      def transform_data
        # NOTE: the CAVE artifact camel keys are spelled "decendent" (see Cave::FieldCatalog
        # DEATH_CERTIFICATE); read those to match the incoming data. The output keys keep the
        # correct "DECEDENT" spelling expected downstream.
        {
          'DECEDENT_FULL_NAME' => build_name(attrs[:decendentFullName]&.transform_keys(&:to_s))[:full],
          'DECEDENT_SSN' => attrs[:decendentSsn],
          'DECEDENT_DATE_OF_DEATH' => format_date(attrs[:decendentDateOfDeath]),
          'DECEDENT_DATE_OF_DISPOSITION' => format_date(attrs[:decendentDateOfDisposition]),
          'CAUSE_OF_DEATH' => attrs[:causeOfDeath],
          'UNDERLYING_CAUSE_OF_DEATH_B' => attrs[:underlyingCauseOfDeathB],
          'UNDERLYING_CAUSE_OF_DEATH_C' => attrs[:underlyingCauseOfDeathC],
          'UNDERLYING_CAUSE_OF_DEATH_D' => attrs[:underlyingCauseOfDeathD],
          'MANNER_OF_DEATH' => attrs[:mannerOfDeath],
          'DECEDENT_MARITAL_STATUS' => attrs[:decendentMaritalStatus]
        }
      end
    end

    class Dd214
      include Mms::DataFormatting
      attr_reader :attrs

      def initialize(attributes)
        @attrs = attributes
      end

      def transform_data
        {
          'VETERAN_NAME' => build_name(@attrs[:veteranName]&.transform_keys(&:to_s))[:full],
          'VETERAN_SSN' => @attrs[:veteranSsn],
          'VETERAN_DOB' => format_date(@attrs[:veteranDob]),
          'BRANCH_OF_SERVICE' => @attrs[:branchOfService],
          'GRADE_RATE_RANK' => @attrs[:gradeRateRank],
          'PAY_GRADE' => @attrs[:payGrade],
          'DATE_INDUCTED' => format_date(@attrs[:dateInducted]),
          'DATE_ENTERED_ACTIVE_SERVICE' => format_date(@attrs[:dateEnteredActiveService]),
          'DATE_SEPARATED_ACTIVE_SERVICE' => format_date(@attrs[:dateSeparatedFromService]),
          'CAUSE_OF_SEPARATION' => @attrs[:causeOfSeparation],
          'CHARACTER_OF_SERVICE' => @attrs[:characterOfService],
          'SEPARATION_TYPE' => @attrs[:separationType],
          'SEPARATION_CODE' => @attrs[:separationCode]
        }
      end
    end
  end
end
