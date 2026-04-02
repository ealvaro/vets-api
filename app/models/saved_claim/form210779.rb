# frozen_string_literal: true

class SavedClaim::Form210779 < SavedClaim
  include IbmDataDictionary

  FORM = '21-0779'
  NURSING_HOME_DOCUMENT_TYPE = 222

  def process_attachments!
    # Form 21-0779 does not support user-uploaded attachments in MVP
    Lighthouse::SubmitBenefitsIntakeClaim.perform_async(id)
  end

  # Required for Lighthouse Benefits Intake API submission
  # CMP = Compensation (for disability claims)
  def business_line
    'CMP'
  end

  # VA Form 21-0779 - Request for Nursing Home Information in Connection with Claim for Aid & Attendance
  # see LighthouseDocument::DOCUMENT_TYPES
  def document_type
    NURSING_HOME_DOCUMENT_TYPE
  end

  def send_confirmation_email
    return unless id

    unless Flipper.enabled?(:form_0779_submission_email_notification)
      StatsD.increment('api.form210779.email.skipped_feature_flag')
      return
    end

    Form210779SubmissionEmailJob.perform_async(id)
    StatsD.increment('api.form210779.email.queued')
  rescue => e
    StatsD.increment('api.form210779.email.queue_failure')
    Rails.logger.error(
      'SavedClaim::Form210779 failed to queue confirmation email',
      saved_claim_id: id,
      error: e.class.name,
      message: e.message
    )
  end

  # Override to_pdf to add nursing home official signature stamp
  def to_pdf(file_name = nil, fill_options = {})
    pdf_path = PdfFill::Filler.fill_form(self, file_name, fill_options)
    PdfFill::Forms::Va210779.stamp_signature(pdf_path, parsed_form)
  end

  def metadata_for_benefits_intake
    { veteranFirstName: parsed_form.dig('veteranInformation', 'fullName', 'first'),
      veteranLastName: parsed_form.dig('veteranInformation', 'fullName', 'last'),
      fileNumber: parsed_form.dig('veteranInformation', 'veteranId', 'ssn'),
      zipCode: zip_code_for_metadata,
      businessLine: business_line,
      docType: "StructuredData:#{FORM}" }
  end

  # Convert form data to IBM MMS VBA Data Dictionary format
  # @return [Hash] VBA Data Dictionary payload for form 21-0779
  # Reference: 0779 Data Dictionary Test Final (1).xlsx
  def to_ibm
    build_ibm_payload(parsed_form)
  end

  def veteran_name
    first = parsed_form.dig('veteranInformation', 'fullName', 'first')
    last = parsed_form.dig('veteranInformation', 'fullName', 'last')
    "#{first} #{last}".strip.presence || 'Veteran'
  end

  private

  def zip_code_for_metadata
    parsed_form.dig('nursingHomeInformation', 'nursingHomeAddress', 'postalCode')
  end

  # Build the IBM data dictionary payload from the parsed claim form
  # @param form [Hash]
  # @return [Hash]
  def build_ibm_payload(form)
    build_veteran_fields(form)
      .merge(build_claimant_fields_section(form))
      .merge(build_nursing_home_fields(form))
      .merge(build_general_information_fields(form))
      .merge(build_form_metadata_fields)
  end

  # Build veteran identification fields (Section I)
  # @param form [Hash]
  # @return [Hash]
  def build_veteran_fields(form)
    vet_info = form['veteranInformation'] || {}
    vet_id = vet_info['veteranId'] || {}
    full_name = vet_info['fullName'] || {}

    build_veteran_basic_fields(vet_info)
      .merge({
               'VETERAN_NAME' => build_full_name(full_name).to_s,
               'VETERAN_SSN' => vet_id['ssn'].to_s,
               'VA_FILE_NUMBER' => vet_id['vaFileNumber'].to_s
             })
  end

  # Build claimant information fields (Section II - Boxes 5-8)
  # @param form [Hash]
  # @return [Hash]
  def build_claimant_fields_section(form)
    claimant_info = form['claimantInformation'] || {}
    claimant_id = claimant_info['veteranId'] || {}
    full_name = claimant_info['fullName'] || {}

    fields = build_claimant_fields(claimant_info)

    # Add full name field
    fields['CLAIMANT_NAME'] = build_full_name(full_name).to_s

    # Override SSN with correct path (from veteranId object)
    fields['CLAIMANT_SSN'] = claimant_id['ssn'].to_s

    # Box 7: VA File Number
    fields['CL_FILE_NUMBER'] = claimant_id['vaFileNumber'].to_s

    fields
  end

  # Build nursing home facility information fields (Section III - Boxes 9-10)
  # @param form [Hash]
  # @return [Hash]
  def build_nursing_home_fields(form)
    nursing_home = form['nursingHomeInformation'] || {}
    nursing_address = nursing_home['nursingHomeAddress'] || {}

    {
      # Box 9: Name of nursing home
      'NAME_FACILITY_C' => nursing_home['nursingHomeName'].to_s,
      # Box 10: Address of nursing home
      'FACILITY_ADDRESS_LINE1_C' => nursing_address['street'].to_s,
      'FACILITY_ADDRESS_LINE2_C' => nursing_address['street2'].to_s,
      'FACILITY_ADDRESS_CITY_C' => nursing_address['city'].to_s,
      'FACILITY_ADDRESS_STATE_C' => nursing_address['state'].to_s,
      'FACILITY_ADDRESS_COUNTRY_C' => nursing_address['country'].to_s,
      'FACILITY_ADDRESS_ZIP_C' => nursing_address['postalCode'].to_s
    }
  end

  # Build general information fields (Section IV - Boxes 11-21)
  # @param form [Hash]
  # @return [Hash]
  def build_general_information_fields(form)
    general_info = form['generalInformation'] || {}

    build_medicaid_fields(general_info)
      .merge(build_cost_and_care_fields(general_info))
      .merge(build_nursing_official_fields(general_info))
  end

  # Build Medicaid-related fields (Boxes 12-14)
  def build_medicaid_fields(general_info)
    {
      'DATE_ADMISSION_TO_FACILITY_C' => format_date_for_ibm(general_info['admissionDate']).to_s,
      'MEDICAID_APPROVED_Y' => build_checkbox_value(general_info['medicaidFacility'] == true),
      'MEDICAID_APPROVED_N' => build_checkbox_value(general_info['medicaidFacility'] == false),
      'MEDICAID_APPLIED_Y' => build_checkbox_value(general_info['medicaidApplication'] == true),
      'MEDICAID_APPLIED_N' => build_checkbox_value(general_info['medicaidApplication'] == false),
      'MEDICAID_COVERAGE_Y' => build_checkbox_value(general_info['patientMedicaidCovered'] == true),
      'MEDICAID_COVERAGE_N' => build_checkbox_value(general_info['patientMedicaidCovered'] == false),
      'MEDICAID_START' => format_date_for_ibm(general_info['medicaidStartDate']).to_s
    }
  end

  # Build cost and care type fields (Boxes 15-16)
  def build_cost_and_care_fields(general_info)
    monthly_costs = general_info['monthlyCosts']

    {
      'OUT_OF_POCKET' => format_currency_for_ibm(monthly_costs).to_s,
      'OUT_OF_POCKET_THSNDS' => extract_currency_thousands(monthly_costs).to_s,
      'OUT_OF_POCKET_HNDRDS' => extract_currency_hundreds(monthly_costs).to_s,
      'OUT_OF_POCKET_CENTS' => extract_currency_cents(monthly_costs).to_s,
      'SKILLED_CARE' => build_checkbox_value(general_info['certificationLevelOfCare'] == 'skilled'),
      'INTERMEDIATE_CARE' => build_checkbox_value(general_info['certificationLevelOfCare'] == 'intermediate')
    }
  end

  # Build nursing home official fields (Boxes 17-21)
  def build_nursing_official_fields(general_info)
    {
      'NAME_COMPLETING_WORKSHEET_C' => general_info['nursingOfficialName'].to_s,
      'ROLE_PERFORM_AT_FACILITY_C' => general_info['nursingOfficialTitle'].to_s,
      'FACILITY_TELEPHONE_NUMBER_C' => format_phone_for_ibm(general_info['nursingOfficialPhoneNumber']).to_s,
      'SIGNATURE_OF_PROVIDER_C' => general_info['signature'].to_s,
      'SIGNATURE_DATE_PROVIDER_C' => format_date_for_ibm(general_info['signatureDate']).to_s
    }
  end

  # Build form metadata and system fields
  # @return [Hash]
  def build_form_metadata_fields
    {
      'FLASH_TEXT' => '',
      'CB_VA_STAMP' => 0, # VA date stamp not applied for online submissions via SavedClaim path
      'FORM_TYPE_1' => 'VA FORM 21-0779, SEP 2023'
    }
  end

  # Extract thousands portion from currency amount
  # Fixed 3-digit format, returns "000" if no thousands
  # @param amount [String, Integer, Float, nil] Numeric amount
  # @return [String] Thousands portion (e.g., "130" from 130000.50, "000" from 9.50)
  def extract_currency_thousands(amount)
    return '000' if amount.nil? || amount.to_s.strip.empty?

    numeric_value = amount.to_s.gsub(/[^0-9.]/, '').to_f
    thousands = (numeric_value / 1000).floor
    thousands.positive? ? thousands.to_s : '000'
  end

  # Extract hundreds portion from currency amount
  # Fixed 3-digit format with leading zeros
  # @param amount [String, Integer, Float, nil] Numeric amount
  # @return [String] Hundreds portion with leading zeros (e.g., "000" from 3000.50, "009" from 9.50)
  def extract_currency_hundreds(amount)
    return '000' if amount.nil? || amount.to_s.strip.empty?

    numeric_value = amount.to_s.gsub(/[^0-9.]/, '').to_f
    hundreds = (numeric_value % 1000).floor
    format('%03d', hundreds)
  end

  # Extract cents portion from currency amount
  # Fixed 2-digit format with leading zeros
  # @param amount [String, Integer, Float, nil] Numeric amount
  # @return [String] Cents portion (e.g., "50" from 3000.50, "00" from 9.00)
  def extract_currency_cents(amount)
    return '00' if amount.nil? || amount.to_s.strip.empty?

    numeric_value = amount.to_s.gsub(/[^0-9.]/, '').to_f
    cents = ((numeric_value % 1) * 100).round
    format('%02d', cents)
  end
end
