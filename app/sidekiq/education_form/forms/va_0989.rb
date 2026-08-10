# frozen_string_literal: true

module EducationForm::Forms
  class VA0989 < Base
    NOT_APPLICABLE = 'N/A'
    UNANSWERED = 'U/A'

    def header_form_type
      'V0989'
    end

    def benefit_type
      '33'
    end

    def applicant_name
      @applicant.applicantName
    end

    def applicant_ssn
      @applicant.vaFileNumber.presence || @applicant.ssn
    end

    def va_file_number
      applicant_ssn
    end

    def home_phone
      optional_value(@applicant.homePhone)
    end

    def mobile_phone
      optional_value(@applicant.mobilePhone)
    end

    def remarks
      optional_value(@applicant.remarks)
    end

    def closed_school_name_and_address
      return NOT_APPLICABLE unless school_closed_questions_visible?

      text = [
        @applicant.closedSchoolName,
        full_address_with_street3(@applicant.closedSchoolAddress)
      ].compact_blank.join("\n")

      text.presence || UNANSWERED
    end

    def new_school_and_program_name
      return NOT_APPLICABLE unless new_school_questions_visible?

      text = [@applicant.newSchoolName, @applicant.newProgramName].compact_blank.join("\n")
      text.presence || UNANSWERED
    end

    def conditional_yesno(value, visible:)
      return NOT_APPLICABLE unless visible
      return UNANSWERED if value.nil?

      value ? 'YES' : 'NO'
    end

    def conditional_date(date_string, visible:)
      return NOT_APPLICABLE unless visible
      return UNANSWERED if date_string.blank?

      format_date(date_string)
    end

    def attestation_signature
      return NOT_APPLICABLE unless school_closed_questions_visible?
      return UNANSWERED if @applicant.attestationName.blank?

      @applicant.attestationName
    end

    def attestation_date
      conditional_date(@applicant.attestationDate, visible: school_closed_questions_visible?)
    end

    def school_closed_questions_visible?
      @applicant.schoolWasClosed == true
    end

    def withdraw_date_visible?
      school_closed_questions_visible? && @applicant.withdrewPriorToClosing == true
    end

    def new_school_questions_visible?
      school_closed_questions_visible? && @applicant.enrolledAtNewSchool == true
    end

    def format_date(date_string)
      return '' if date_string.blank?

      Date.parse(date_string.to_s).strftime('%m/%d/%Y')
    rescue ArgumentError, TypeError
      date_string.to_s
    end

    private

    def optional_value(value)
      return UNANSWERED if value.blank?

      value.to_s
    end
  end
end
