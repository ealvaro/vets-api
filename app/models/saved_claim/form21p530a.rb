# frozen_string_literal: true

class SavedClaim::Form21p530a < SavedClaim
  include IbmDataDictionary

  FORM = '21P-530a'
  DEFAULT_ZIP_CODE = '00000'

  validates :form, presence: true

  def form_schema
    schema = JSON.parse(Openapi::Requests::Form21p530a::FORM_SCHEMA.to_json)
    schema['components'] = JSON.parse(Openapi::Components::ALL.to_json)
    schema
  end

  def process_attachments!
    Lighthouse::SubmitBenefitsIntakeClaim.perform_async(id)
  end

  def send_confirmation_email
    # Email functionality not included in MVP
    # recipient_email = parsed_form.dig('burialInformation', 'recipientOrganization', 'email')
    # return unless recipient_email

    # VANotify::EmailJob.perform_async(
    #   recipient_email,
    #   Settings.vanotify.services.va_gov.template_id.form21p530a_confirmation,
    #   {
    #     'organization_name' => organization_name,
    #     'veteran_name' => veteran_name,
    #     'confirmation_number' => confirmation_number,
    #     'date_submitted' => created_at.strftime('%B %d, %Y')
    #   }
    # )
  end

  # SavedClaims require regional_office to be defined
  def regional_office
    [
      'Department of Veterans Affairs',
      'Pension Management Center',
      'P.O. Box 5365',
      'Janesville, WI 53547-5365'
    ].freeze
  end

  # Required for Lighthouse Benefits Intake API submission
  # PMC = Pension Management Center (handles burial benefits)
  def business_line
    'PMC'
  end

  # VBMS document type for burial allowance applications
  def document_type
    540 # Burial/Memorial Benefits
  end

  def attachment_keys
    # Form 21P-530a does not support attachments in MVP
    [].freeze
  end

  # Override to_pdf to add official signature stamp
  # This ensures the signature is included in both the download_pdf endpoint
  # and the Lighthouse Benefits Intake submission
  def to_pdf(file_name = nil, fill_options = {})
    pdf_path = PdfFill::Filler.fill_form(self, file_name, fill_options)
    PdfFill::Forms::Va21p530a.stamp_signature(pdf_path, parsed_form)
  end

  # Required metadata format for Lighthouse Benefits Intake API submission
  # This method extracts veteran identity information and organization address
  # to ensure proper routing and indexing in VBMS
  def metadata_for_benefits_intake
    { veteranFirstName: parsed_form.dig('veteranInformation', 'fullName', 'first'),
      veteranLastName: parsed_form.dig('veteranInformation', 'fullName', 'last'),
      fileNumber: parsed_form.dig('veteranInformation', 'vaFileNumber') || parsed_form.dig('veteranInformation', 'ssn'),
      zipCode: zip_code_for_metadata,
      businessLine: business_line,
      docType: "StructuredData:#{FORM}" }
  end

  # Convert form data to IBM GCIO VBA Data Dictionary format
  # Returns all 48 fields defined in the VA Forms - Data Dictionary
  # Mapping based on Form 21P-530a OCT 2024 Data Dictionary
  def to_ibm
    vet_info = parsed_form['veteranInformation'] || {}
    burial_info = parsed_form['burialInformation'] || {}
    certification = parsed_form['certification'] || {}
    service_periods_data = parsed_form['veteranServicePeriods'] || {}

    build_ibm_hash(vet_info, burial_info, certification, service_periods_data)
  end

  def veteran_name
    first = parsed_form.dig('veteranInformation', 'fullName', 'first')
    last = parsed_form.dig('veteranInformation', 'fullName', 'last')
    "#{first} #{last}".strip.presence || 'Veteran'
  end

  private

  def organization_name
    parsed_form.dig('burialInformation', 'recipientOrganization', 'name') ||
      parsed_form.dig('burialInformation', 'nameOfStateCemeteryOrTribalOrganization')
  end

  def zip_code_for_metadata
    parsed_form.dig('burialInformation', 'recipientOrganization', 'address', 'postalCode') || DEFAULT_ZIP_CODE
  end

  # Build the IBM VBA Data Dictionary hash with all 48 required fields
  # @param vet_info [Hash] Veteran information from parsed form
  # @param burial_info [Hash] Burial information from parsed form
  # @param certification [Hash] Certification information from parsed form
  # @param service_periods_data [Hash] Veteran service periods data from parsed form
  # @return [Hash] VBA Data Dictionary payload
  def build_ibm_hash(vet_info, burial_info, certification, service_periods_data)
    full_name = vet_info['fullName'] || {}
    place_of_burial = burial_info['placeOfBurial'] || {}
    recipient_org = burial_info['recipientOrganization'] || {}

    build_veteran_fields(vet_info, full_name)
      .merge(build_service_history_fields(service_periods_data))
      .merge(build_burial_fields(burial_info, place_of_burial))
      .merge(build_recipient_org_fields(recipient_org))
      .merge(build_certification_fields(certification))
  end

  def build_veteran_fields(vet_info, full_name)
    place_of_birth = vet_info['placeOfBirth'] || {}
    pob_city = place_of_birth['city']
    pob_state = place_of_birth['state']
    place_of_birth_str = [pob_city, pob_state].compact.reject(&:empty?).join(', ').presence

    {
      'VETERAN_FIRST_NAME' => full_name['first'].to_s,
      'VETERAN_MIDDLE_INITIAL' => extract_middle_initial(full_name['middle']).to_s,
      'VETERAN_LAST_NAME' => full_name['last'].to_s,
      'VETERAN_NAME' => build_full_name(full_name).to_s,
      'VETERAN_SSN' => vet_info['ssn'].to_s,
      'VETERAN_SERVICE_NUMBER' => vet_info['vaServiceNumber'].to_s,
      'VA_FILE_NUMBER' => vet_info['vaFileNumber'].to_s,
      'VETERAN_DOB' => format_date_for_ibm(vet_info['dateOfBirth']).to_s,
      'VETERAN_PLACE_OF_BIRTH' => place_of_birth_str.to_s,
      'VETERAN_DATE_OF_DEATH' => format_date_for_ibm(vet_info['dateOfDeath']).to_s
    }
  end

  def build_burial_fields(burial_info, place_of_burial)
    {
      'ORG_CLAIMING_ALLOWANCE' => burial_info['nameOfStateCemeteryOrTribalOrganization'].to_s,
      'CEMETERY_NAME' => place_of_burial['stateCemeteryOrTribalCemeteryName'].to_s,
      'CEMETERY_LOCATION' => place_of_burial['stateCemeteryOrTribalCemeteryLocation'].to_s,
      'VETERAN_DATE_OF_BURIAL' => format_date_for_ibm(burial_info['dateOfBurial']).to_s
    }
  end

  # Build service history fields for up to 3 service periods (Boxes 8-10)
  # @param service_periods_data [Hash] Veteran service periods data
  # @return [Hash] VBA Data Dictionary service history fields
  def build_service_history_fields(service_periods_data)
    service_periods = service_periods_data['periods'] || []
    fields = {}

    # Always create all 3 service period slots (Boxes 8-9)
    (1..3).each do |suffix|
      period = service_periods[suffix - 1] || {}
      fields["BRANCH_OF_SERVICE_#{suffix}"] = period['serviceBranch'].to_s
      fields["DATE_ENTERED_TO_SERVICE_#{suffix}"] =
        format_date_for_ibm(period['dateEnteredService']).to_s
      fields["PLACE_ENTERED_TO_SERVICE_#{suffix}"] = period['placeEnteredService'].to_s
      fields["GRADE_RANK_#{suffix}"] = period['rankAtSeparation'].to_s
      fields["SEPARATION_DATE_#{suffix}"] = format_date_for_ibm(period['dateLeftService']).to_s
      fields["SEPARATION_PLACE_#{suffix}"] = period['placeLeftService'].to_s
    end

    # Box 10 - Veteran served under other name
    fields['VET_NAME_OTHER'] = service_periods_data['servedUnderDifferentName'].to_s

    fields
  end

  # Build recipient organization fields (Boxes 14-16)
  # @param recipient_org [Hash] Recipient organization information
  # @return [Hash] VBA Data Dictionary recipient organization fields
  def build_recipient_org_fields(recipient_org)
    address = recipient_org['address'] || {}

    {
      'REP_NAME' => recipient_org['name'].to_s,
      'REP_PHONE_NUMBER' => recipient_org['phoneNumber'].to_s,
      'REP_ADDRESS_LINE1' => address['streetAndNumber'].to_s,
      'REP_ADDRESS_LINE2' => address['aptOrUnitNumber'].to_s,
      'REP_ADDRESS_CITY' => address['city'].to_s,
      'REP_ADDRESS_STATE' => address['state'].to_s,
      'REP_ADDRESS_ZIP5' => address['postalCode'].to_s,
      'REP_ADDRESS' => format_recipient_address(address).to_s
    }
  end

  def build_certification_fields(certification)
    date_signed = certification['dateSigned'] || parsed_form['dateSigned'] || created_at&.to_date&.iso8601

    {
      'OFFICIAL_SIGNATURE' => certification['signature'].to_s,
      'OFFICIAL_TITLE' => certification['titleOfStateOrTribalOfficial'].to_s,
      'DATE_SIGNED' => format_date_for_ibm(date_signed).to_s,
      'REMARKS' => parsed_form['remarks'].to_s,
      'VETERAN_SSN_1' => parsed_form.dig('veteranInformation', 'ssn').to_s,
      'FORM_TYPE' => 'VA FORM 21P-530a, OCT 2024',
      'FORM_TYPE_1' => 'VA FORM 21P-530a, OCT 2024'
    }
  end

  # Format full address for recipient organization (different field names than default)
  def format_recipient_address(address)
    return nil unless address

    parts = [
      address['streetAndNumber'],
      address['aptOrUnitNumber'],
      address['city'],
      address['state'],
      address['postalCode']
    ].compact.reject(&:empty?)

    parts.join(', ').presence
  end
end
