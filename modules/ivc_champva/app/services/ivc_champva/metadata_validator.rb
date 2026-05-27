# frozen_string_literal: true

require 'datadog'

module IvcChampva
  class MetadataValidator
    def self.validate(metadata)
      Datadog::Tracing.trace('IVC Champva Forms - Validate Metadata') do
        name_prefix = Flipper.enabled?(:champva_update_metadata_keys) ? 'sponsor' : 'veteran'

        validate_first_name(metadata, name_prefix)
          .then { |m| validate_last_name(m, name_prefix) }
          .then { |m| validate_file_number(m) }
          .then { |m| validate_zip_code(m) }
          .then { |m| validate_source(m) }
          .then { |m| validate_doc_type(m) }
      end
    end

    def self.validate_first_name(metadata, name_prefix = 'veteran')
      validate_presence_and_stringiness(metadata["#{name_prefix}FirstName"], "#{name_prefix} first name")
      metadata["#{name_prefix}FirstName"] =
        I18n.transliterate(metadata["#{name_prefix}FirstName"]).gsub(%r{[^a-zA-Z\-/\s]}, '').strip.first(50)

      metadata
    end

    def self.validate_last_name(metadata, name_prefix = 'veteran')
      validate_presence_and_stringiness(metadata["#{name_prefix}LastName"], "#{name_prefix} last name")
      metadata["#{name_prefix}LastName"] =
        I18n.transliterate(metadata["#{name_prefix}LastName"]).gsub(%r{[^a-zA-Z\-/\s]}, '').strip.first(50)

      metadata
    end

    def self.validate_file_number(metadata)
      return metadata if metadata['fileNumber'].blank?

      validate_presence_and_stringiness(metadata['fileNumber'], 'file number')
      unless metadata['fileNumber'].match?(/^\d{8,9}$/)
        raise ArgumentError, 'file number is invalid. It must be 8 or 9 digits'
      end

      metadata
    end

    def self.validate_zip_code(metadata)
      zip_code = metadata['zipCode']
      if metadata['country'] == 'USA' && !zip_code.nil?
        validate_presence_and_stringiness(zip_code, 'zip code')
        zip_code = zip_code.dup.gsub(/[^0-9]/, '')
        zip_code.insert(5, '-') if zip_code.match?(/\A[0-9]{9}\z/)
        zip_code = '00000' unless zip_code.match?(/\A[0-9]{5}(-[0-9]{4})?\z/)
      else
        zip_code = '00000'
      end

      metadata['zipCode'] = zip_code

      metadata
    end

    def self.validate_source(metadata)
      validate_presence_and_stringiness(metadata['source'], 'source')

      metadata
    end

    def self.validate_doc_type(metadata)
      validate_presence_and_stringiness(metadata['docType'], 'doc type')

      metadata
    end

    def self.validate_presence_and_stringiness(value, error_label)
      raise ArgumentError, "#{error_label} is missing" unless value
      raise ArgumentError, "#{error_label} is not a string" if value.class != String
    end

    def self.validate_docs_only_resubmission(data)
      submission_type = data['submission_type'].to_s.strip.downcase

      validate_docs_only_supporting_docs(data['supporting_docs'])
      validate_docs_only_contact_info(data['primary_contact_info'])
      validate_docs_only_applicants(data['applicants'], submission_type)
      validate_docs_only_veteran(data['veteran'], submission_type)
      validate_presence_and_stringiness(data['certifier_role'], 'certifier_role')
      validate_presence_and_stringiness(data['statement_of_truth_signature'], 'statement_of_truth_signature')
      validate_presence_and_stringiness(data.dig('certification', 'date'), 'certification date')
    end

    def self.validate_docs_only_resubmission_cst(data)
      validate_docs_only_supporting_docs(data['supporting_docs'])
    end

    def self.validate_docs_only_supporting_docs(docs)
      raise ArgumentError, 'supporting_docs is missing' if docs.blank?

      docs.each_with_index do |doc, i|
        validate_presence_and_stringiness(doc['confirmation_code'], "supporting_docs[#{i}] confirmation_code")
      end
    end

    def self.validate_docs_only_contact_info(pci)
      raise ArgumentError, 'primary_contact_info is missing' if pci.blank?

      validate_presence_and_stringiness(pci['email'], 'primary_contact_info email')
    end

    def self.validate_docs_only_applicants(applicants, submission_type)
      raise ArgumentError, 'applicants is missing' if applicants.blank?

      applicants.each_with_index do |app, i|
        validate_presence_and_stringiness(app.dig('applicant_name', 'first'), "applicants[#{i}] first name")
        validate_presence_and_stringiness(app.dig('applicant_name', 'last'), "applicants[#{i}] last name")
        validate_presence_and_stringiness(app['applicant_dob'], "applicants[#{i}] applicant_dob")
        if submission_type == 'enrollment'
          validate_presence_and_stringiness(app['applicant_member_number'], "applicants[#{i}] applicant_member_number")
        end
      end
    end

    def self.validate_docs_only_veteran(vet, submission_type)
      raise ArgumentError, 'veteran is missing' if vet.blank?

      return unless submission_type == 'existing'

      validate_presence_and_stringiness(vet.dig('full_name', 'first'), 'veteran first name')
      validate_presence_and_stringiness(vet.dig('full_name', 'last'), 'veteran last name')
      validate_presence_and_stringiness(vet['ssn_or_tin'], 'veteran ssn_or_tin')
      validate_presence_and_stringiness(vet['date_of_birth'], 'veteran date_of_birth')
    end
  end
end
