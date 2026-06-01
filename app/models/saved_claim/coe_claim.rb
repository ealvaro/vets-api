# frozen_string_literal: true

class SavedClaim::CoeClaim < SavedClaim
  include CoeClaimFormValidation

  FORM = '26-1880'
  REBUILD_FORM_VERSIONS = [2, 3].freeze

  def form_matches_schema
    return super unless rebuild_form_version?

    return unless form_is_string

    validate_coe_rebuild_form
  end

  def send_to_lgy(edipi:, icn:)
    @edipi = edipi
    @icn = icn

    # If the EDIPI is blank, throw an error
    if @edipi.blank?
      Rails.logger.error('COE application cannot be submitted without an edipi!')
    # Otherwise, submit the claim to the LGY API
    else
      Rails.logger.info('Begin COE claim submission to LGY API', guid:)
      response = lgy_service.put_application(payload: prepare_form_data)
      Rails.logger.info('COE claim submitted to LGY API', guid:, reference_number: response['reference_number'])

      process_attachments!
      response['reference_number']
    end
  rescue Common::Client::Errors::ClientError => e
    # 502-503 errors happen frequently from LGY endpoint at the time of implementation
    # and have not been corrected yet. We would like to seperate these from our monitoring for now
    # See https://va.ghe.com/software/va.gov-team/issues/90411
    # and https://va.ghe.com/software/va.gov-team/issues/91111
    if [503, 504].include?(e.status)
      Rails.logger.info('LGY server unavailable or unresponsive',
                        { status: e.status, messsage: e.message, body: e.body })
    else
      Rails.logger.error('LGY API returned error', { status: e.status, messsage: e.message, body: e.body })
    end

    raise e
  end

  def regional_office
    []
  end

  private

  def rebuild_form_version?
    parsed_form.is_a?(Hash) && REBUILD_FORM_VERSIONS.include?(coe_form_version)
  rescue JSON::ParserError
    false
  end

  # rubocop:disable Metrics/MethodLength
  def prepare_form_data
    postal_code, postal_code_suffix = get_value_by_form_version('zip').to_s.split('-', 2)
    form_copy = {
      'status' => 'SUBMITTED',
      'veteran' => {
        'firstName' => parsed_form['fullName']['first'],
        'middleName' => parsed_form['fullName']['middle'] || '',
        'lastName' => parsed_form['fullName']['last'],
        'suffixName' => parsed_form['fullName']['suffix'] || '',
        'dateOfBirth' => parsed_form['dateOfBirth'],
        'vetAddress1' => get_value_by_form_version('street') || '',
        'vetAddress2' => get_value_by_form_version('street2') || '',
        'vetAddress3' => get_value_by_form_version('street3') || '',
        'vetCity' => get_value_by_form_version('city') || '',
        'vetState' => get_value_by_form_version('state') || '',
        'vetZip' => postal_code,
        'vetZipSuffix' => postal_code_suffix,
        'mailingAddress1' => get_value_by_form_version('street') || '',
        'mailingAddress2' => get_value_by_form_version('street2') || '',
        'mailingAddress3' => get_value_by_form_version('street3') || '',
        'mailingCity' => get_value_by_form_version('city') || '',
        'mailingState' => get_value_by_form_version('state') || '',
        'mailingZip' => postal_code,
        'mailingZipSuffix' => postal_code_suffix || '',
        'contactPhone' => get_value_by_form_version('phone') || '',
        'contactEmail' => get_value_by_form_version('email') || '',
        'vaLoanIndicator' => get_value_by_form_version('vaLoanIndicator'),
        'vaHomeOwnIndicator' => get_value_by_form_version('vaHomeOwnIndicator'),
        'activeDutyIndicator' => get_value_by_form_version('identity') == 'ADSM',
        'disabilityIndicator' => get_value_by_form_version('disabilityIndicator') || false
      },
      'relevantPriorLoans' => [],
      'periodsOfService' => []
    }

    if parsed_form.key?('relevantPriorLoans') || parsed_form['loanHistory']&.key?('relevantPriorLoans')
      relevant_prior_loans(form_copy)
    end
    if parsed_form.key?('periodsOfService') || parsed_form['militaryHistory']&.key?('periodsOfService')
      periods_of_service(form_copy)
    end

    update(form: form_copy.to_json)
    form_copy
  end

  def get_value_by_form_version(field)
    case field
    when 'street', 'street2', 'street3', 'city', 'state', 'zip'
      get_address_field(field)
    when 'phone', 'email'
      get_contact_field(field)
    when 'identity', 'disabilityIndicator', 'periodsOfService'
      get_military_history_field(field)
    when 'files', 'file_attachment_type', 'file_attachment_description'
      get_file_field(field)
    when 'vaLoanIndicator', 'vaHomeOwnIndicator', 'relevantPriorLoans'
      get_loan_field(field)
    end
  end

  def get_address_field(field)
    address_mappings = {
      'street' => { v2: %w[veteran mailingAddress addressLine1], v1: %w[applicantAddress street] },
      'street2' => { v2: %w[veteran mailingAddress addressLine2], v1: %w[applicantAddress street2] },
      'street3' => { v2: %w[veteran mailingAddress addressLine3], v1: %w[applicantAddress street3] },
      'city' => { v2: %w[veteran mailingAddress city], v1: %w[applicantAddress city] },
      'state' => { v2: %w[veteran mailingAddress stateCode], v1: %w[applicantAddress state] },
      'zip' => { v2: %w[veteran mailingAddress zipCode], v1: %w[applicantAddress postalCode] }
    }

    mapping = address_mappings[field]
    path = rebuild_form_version? ? mapping[:v2] : mapping[:v1]
    parsed_form.dig(*path)
  end

  def get_contact_field(field)
    veteran_segment = parsed_form['veteran'] || {}

    case field
    when 'phone'
      if rebuild_form_version?
        home_phone = veteran_segment['homePhone'] || {}
        (home_phone['areaCode'].to_s + home_phone['phoneNumber'].to_s)
      else
        parsed_form['contactPhone']
      end
    when 'email'
      rebuild_form_version? ? veteran_segment.dig('email', 'emailAddress') : parsed_form['contactEmail']
    end
  end

  def get_military_history_field(field)
    case field
    when 'identity'
      rebuild_form_version? ? parsed_form.dig('militaryHistory', 'status') : parsed_form['identity']
    when 'disabilityIndicator'
      rebuild_form_version? ? parsed_form.dig('militaryHistory', 'separatedDueToDisability') : false
    when 'periodsOfService'
      legacy_periods = parsed_form['periodsOfService'] || []
      v2_periods = parsed_form.dig('militaryHistory', 'periodsOfService') || []
      rebuild_form_version? ? v2_periods : legacy_periods
    end
  end

  def get_file_field(field, file = nil)
    case field
    when 'files'
      rebuild_form_version? ? parsed_form['files2'] : parsed_form['files']
    when 'file_attachment_type'
      rebuild_form_version? ? file.dig('additionalData', 'attachmentType') : file['attachmentType']
    when 'file_attachment_description'
      rebuild_form_version? ? file.dig('additionalData', 'attachmentDescription') : file['attachmentDescription']
    end
  end

  def get_loan_field(field)
    legacy_prior_loans = parsed_form['relevantPriorLoans'] || []
    v2_prior_loans = parsed_form.dig('loanHistory', 'relevantPriorLoans') || []

    case field
    when 'vaLoanIndicator'
      rebuild_form_version? ? parsed_form.dig('loanHistory', 'hadPriorLoans') : parsed_form['vaLoanIndicator']
    when 'vaHomeOwnIndicator'
      rebuild_form_version? ? v2_prior_loans.count.positive? : legacy_prior_loans.any?
    when 'relevantPriorLoans'
      rebuild_form_version? ? v2_prior_loans : legacy_prior_loans
    end
  end

  def get_value_by_form_version_from_prior_loan(field, loan)
    case field
    when 'intent'
      rebuild_form_version? ? loan['entitlementRestoration'] : loan['intent']
    end
  end
  # rubocop:enable Metrics/MethodLength

  def lgy_service
    @lgy_service ||= LGY::Service.new(edipi: @edipi, icn: @icn)
  end

  # @param loan_info [Hash] one row of parsed_form['relevantPriorLoans'] from the (legacy) submit payload
  def lgy_row_property_owned?(loan_info)
    return true unless loan_info.key?('propertyOwned')

    v = loan_info['propertyOwned']
    [true, 'true'].include?(v)
  end

  # rubocop:disable Metrics/MethodLength
  def relevant_prior_loans(form_copy)
    get_value_by_form_version('relevantPriorLoans').each do |loan_info|
      pa = loan_info['propertyAddress']
      start_date, paid_off_date =
        if rebuild_form_version?
          [loan_info['loanDate'], '']
        else
          [loan_info['dateRange']['from'], loan_info['dateRange']['to']]
        end
      addr1, addr2, city, state, zip_raw =
        if rebuild_form_version?
          [pa['street1'], pa['street2'] || '', pa['city'], pa['state'], pa['postalCode'].to_s]
        else
          [pa['propertyAddress1'], pa['propertyAddress2'] || '', pa['propertyCity'], pa['propertyState'],
           pa['propertyZip'].to_s]
        end
      property_zip, property_zip_suffix = zip_raw.split('-', 2)
      intent = get_value_by_form_version_from_prior_loan('intent', loan_info)
      form_copy['relevantPriorLoans'] << {
        'vaLoanNumber' => loan_info['vaLoanNumber'].to_s,
        'startDate' => start_date,
        'paidOffDate' => paid_off_date,
        'loanAmount' => loan_info['loanAmount'],
        'loanEntitlementCharged' => loan_info['loanEntitlementCharged'],
        # propertyOwned also maps to the stillOwn indicator on the LGY side;
        # prior-loan rows from the new form omit this on the FE; list membership implies current ownership
        'propertyOwned' => lgy_row_property_owned?(loan_info),
        # In UI: "A one-time restoration of entitlement"
        # In LGY: "One Time Resto"
        'oneTimeRestorationRequested' => intent == 'ONE_TIME_RESTORATION',
        # In UI: "An Interest Rate Reduction Refinance Loan (IRRRL) to refinance the balance of a current VA home loan"
        # In LGY: "IRRRL Ind"
        'irrrlRequested' => %w[IRRRL INTEREST_RATE_REDUCTION_REFINANCE].include?(intent),
        # In UI: "A regular cash-out refinance of a current VA home loan"
        # In LGY: "Cash Out Refi"
        'cashoutRefinaceRequested' => %w[REFI CASH_OUT_REFINANCE].include?(intent),
        # In UI: "An entitlement inquiry only"
        # In LGY: "Entitlement Inquiry Only"
        'noRestorationEntitlementIndicator' => %w[INQUIRY ENTITLEMENT_INQUIRY_ONLY].include?(intent),
        # LGY has requested `homeSellIndicator` always be null
        'homeSellIndicator' => nil,
        'propertyAddress1' => addr1,
        'propertyAddress2' => addr2,
        'propertyCity' => city,
        'propertyState' => state,
        # confirmed OK to omit propertyCounty, but LGY still requires a string
        'propertyCounty' => '',
        'propertyZip' => property_zip,
        'propertyZipSuffix' => property_zip_suffix || ''
      }
    end
  end
  # rubocop:enable Metrics/MethodLength

  def periods_of_service(form_copy)
    get_value_by_form_version('periodsOfService').each do |service_info|
      service_branch_value = service_info['serviceBranch']

      if rebuild_form_version?
        military_branch, service_type = map_service_branch_code(service_branch_value)
        log_version_string = 'COE periods_of_service using v2 mapping'
      else
        military_branch, service_type = map_legacy_service_branch(service_branch_value)
        log_version_string = 'COE periods_of_service using legacy mapping'
      end

      Rails.logger.info(log_version_string,
                        { guid:, form_value: service_branch_value, mapped_branch: military_branch,
                          mapped_type: service_type })

      form_copy['periodsOfService'] << {
        'enteredOnDuty' => service_info['dateRange']['from'],
        'releasedActiveDuty' => service_info['dateRange']['to'],
        'militaryBranch' => military_branch,
        'serviceType' => service_type,
        'disabilityIndicator' => get_value_by_form_version('disabilityIndicator') || false
      }
    end
  end

  def map_service_branch_code(service_branch_code)
    mapping = LGY::Constants::SERVICE_BRANCH_MAPPING[service_branch_code]

    if mapping
      [mapping[:branch], mapping[:service_type]]
    else
      Rails.logger.warn('COE unknown service branch code', { guid:, form_value: service_branch_code })
      %w[OTHER ACTIVE_DUTY]
    end
  end

  # LEGACY METHOD: Keep existing string-based logic exactly as-is (to be removed when v2 form is fully rolled out)
  def map_legacy_service_branch(service_branch_string)
    # values from the FE for military_branch are:
    # ["Air Force", "Air Force Reserve", "Air National Guard", "Army", "Army National Guard", "Army Reserve",
    # "Coast Guard", "Coast Guard Reserve", "Marine Corps", "Marine Corps Reserve", "Navy", "Navy Reserve"]
    # these need to be formatted because LGY only accepts [ARMY, NAVY, MARINES, AIR_FORCE, COAST_GUARD, OTHER]
    # and then we have to pass in ACTIVE_DUTY or RESERVE_NATIONAL_GUARD for service_type
    military_branch = service_branch_string.parameterize.underscore.upcase
    service_type = 'ACTIVE_DUTY'

    # "Marine Corps" must be converted to "Marines" here, so that the `.any`
    # block below can convert "Marine Corps" and "Marine Corps Reserve" to
    # "MARINES", to meet LGY's requirements.
    military_branch = military_branch.gsub('MARINE_CORPS', 'MARINES')

    %w[RESERVE NATIONAL_GUARD].any? do |service_branch|
      next unless military_branch.include?(service_branch)

      index = military_branch.index('_NATIONAL_GUARD') || military_branch.index('_RESERVE')
      military_branch = military_branch[0, index]
      # "Air National Guard", unlike "Air Force Reserve", needs to be manually
      # transformed to AIR_FORCE here, to meet LGY's requirements.
      military_branch = 'AIR_FORCE' if military_branch == 'AIR'
      service_type = 'RESERVE_NATIONAL_GUARD'
    end

    [military_branch, service_type]
  end

  def process_attachments!
    supporting_documents = get_value_by_form_version('files')
    if supporting_documents.present?
      files = PersistentAttachment.where(guid: supporting_documents.pluck('confirmationCode'))
      files.find_each { |f| f.update(saved_claim_id: id) }

      prepare_document_data
    end
  end

  def prepare_document_data
    persistent_attachments.each do |attachment|
      file_extension = File.extname(URI.parse(attachment.file.url).path)
      files = get_value_by_form_version('files') || []
      claim_file_data = files.find { |f| f['confirmationCode'] == attachment['guid'] } ||
                        { 'attachmentType' => '', 'attachmentDescription' => '' }

      if %w[.jpg .jpeg .png .pdf].include? file_extension.downcase
        file_path = Common::FileHelpers.generate_clamav_temp_file(attachment.file.read)

        File.rename(file_path, "#{file_path}#{file_extension}")
        file_path = "#{file_path}#{file_extension}"

        document_data = {
          # This is one of the options in the "Document Type" dropdown on the
          # "Your supporting documents" step of the COE form. E.g. "Discharge or
          # separation papers (DD214)"
          'documentType' => get_file_field('file_attachment_type', claim_file_data),
          # This is the vet's own description of a document, after selecting
          # "other" as the `attachmentType`.
          'description' => get_file_field('file_attachment_description', claim_file_data),
          'contentsBase64' => Base64.encode64(File.read(file_path)),
          'fileName' => attachment.file.metadata['filename']
        }

        lgy_service.post_document(payload: document_data)
        Common::FileHelpers.delete_file_if_exists(file_path)
      end
    end
  end
end
