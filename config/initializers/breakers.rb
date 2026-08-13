# frozen_string_literal: true

require 'bb/configuration'
require 'breakers/statsd_plugin'
require 'caseflow/configuration'
require 'central_mail/configuration'
require 'debt_management_center/debts_configuration'
require 'decision_review/configuration'
require 'vye/dgib/service'
require 'dgi/automation/configuration'
require 'dgi/contact_info/configuration'
require 'dgi/eligibility/configuration'
require 'dgi/status/configuration'
require 'dgi/submission/configuration'
require 'dgi/letters/configuration'
require 'evss/claims_service'
require 'evss/common_service'
require 'evss/disability_compensation_form/configuration'
require 'evss/documents_service'
require 'evss/letters/service'
require 'gi/configuration'
require 'gibft/configuration'
require 'hca/configuration'
require 'lighthouse/benefits_education/configuration'
require 'mdot/configuration'
require 'mhv_ac/configuration'
require 'mpi/configuration'
require 'pagerduty/configuration'
require 'preneeds/configuration'
require 'rx/configuration'
require 'sm/configuration'
require 'search/configuration'
require 'search_gsa/configuration'
require 'search_click_tracking/configuration'
require 'va_profile/address_validation/v3/configuration'
require 'va_profile/contact_information/v2/configuration'
require 'va_profile/communication/configuration'
require 'va_profile/demographics/configuration'
require 'va_profile/military_personnel/configuration'
require 'va_profile/person_settings/configuration'
require 'va_profile/veteran_status/configuration'
require 'iam_ssoe_oauth/configuration'
require 'vetext/service'
require 'veteran_enrollment_system/associations/configuration'
require 'veteran_enrollment_system/base_configuration'
require 'unified_health_data/configuration'
require 'vha_notification/configuration'
require 'eps/configuration'
require 'ccra/configuration'

# --- Added by breakers audit (lib/**/configuration.rb candidates) ---
require 'apps/configuration'
require 'benefits_intake_service/configuration'
require 'bep/awards/configuration'
require 'bep/claims/configuration'
require 'bep/persons/configuration'
require 'chip/configuration'
require 'contention_classification/configuration'
require 'decision_review/utilities/pdf_validation/configuration'
require 'disability_max_ratings/configuration'
require 'form526_backup_submission/configuration'
require 'form_intake/configuration'
require 'forms/configuration'
require 'forms/submission_statuses/pdf_url_verifier'
require 'hca/enrollment_eligibility/configuration'
require 'ibm/configuration'
require 'kafka/schema_registry/configuration'
require 'lgy/configuration'
require 'lighthouse/auth/client_credentials/configuration'
require 'lighthouse/benefits_claims/configuration'
require 'lighthouse/benefits_discovery/configuration'
require 'lighthouse/benefits_documents/configuration'
require 'lighthouse/benefits_intake/configuration'
require 'lighthouse/benefits_reference_data/configuration'
require 'lighthouse/benefits_reference_data_staging/configuration'
require 'lighthouse/direct_deposit/configuration'
require 'lighthouse/facilities/configuration'
require 'lighthouse/healthcare_cost_and_coverage/configuration'
require 'lighthouse/letters_generator/configuration'
require 'lighthouse/veteran_verification/configuration'
require 'lighthouse/veterans_health/configuration'
require 'mail_automation/configuration'
require 'map/security_token/configuration'
require 'map/sign_up/configuration'
require 'medical_records/bb_internal/configuration'
require 'medical_records/configuration'
require 'medical_records/phr_mgr/configuration'
require 'medical_records/user_eligibility/configuration'
require 'mhv/aal/configuration'
require 'mhv/account_creation/configuration'
require 'res/configuration'
require 'sign_in/idme/configuration'
require 'sign_in/logingov/configuration'
require 'ssoe/configuration'
require 'token_validation/v2/configuration'
require 'va_profile/profile/v3/configuration'
require 'vbs/configuration'
require 'veteran_enrollment_system/enrollment_periods/configuration'
require 'veteran_enrollment_system/form1095_b/configuration'

Rails.application.reloader.to_prepare do
  redis_namespace = Redis::Namespace.new('breakers', redis: $redis)
  # --- Added by breakers audit (lib/**/configuration.rb candidates) ---
  # NOTE: the following classes were intentionally NOT added -- see PR/ticket
  # for disposition:
  #   - BEP::Configuration                              (abstract base; see BEP::Awards / BEP::Persons below)
  #   - EVSS::Configuration                              (abstract base; concrete subclasses registered individually)
  #   - Salesforce::Configuration                        (abstract base; already-registered subclass)
  #   - VAProfile::Configuration                         (abstract base; concrete subclasses registered individually)
  #   - EVSS::DisabilityCompensationForm::Dvp::Configuration (inherits from parent config)
  #   - GI::LCPE::Configuration                          (inherits from parent config)
  services = [
    DebtManagementCenter::DebtsConfiguration.instance.breakers_service,
    Caseflow::Configuration.instance.breakers_service,
    DecisionReview::Configuration.instance.breakers_service,
    Rx::Configuration.instance.breakers_service,
    BB::Configuration.instance.breakers_service,
    BenefitsEducation::Configuration.instance.breakers_service,
    EVSS::ClaimsService.breakers_service,
    EVSS::CommonService.breakers_service,
    EVSS::DisabilityCompensationForm::Configuration.instance.breakers_service,
    EVSS::DocumentsService.breakers_service,
    EVSS::Letters::Configuration.instance.breakers_service,
    Gibft::Configuration.instance.breakers_service,
    GI::Configuration.instance.breakers_service,
    HCA::Configuration.instance.breakers_service,
    MHVAC::Configuration.instance.breakers_service,
    MPI::Configuration.instance.breakers_service,
    Preneeds::Configuration.instance.breakers_service,
    SM::Configuration.instance.breakers_service,
    VeteranEnrollmentSystem::Associations::Configuration.instance.breakers_service,
    VeteranEnrollmentSystem::BaseConfiguration.instance.breakers_service,
    VAProfile::AddressValidation::V3::Configuration.instance.breakers_service,
    VAProfile::ContactInformation::V2::Configuration.instance.breakers_service,
    VAProfile::Communication::Configuration.instance.breakers_service,
    VAProfile::Demographics::Configuration.instance.breakers_service,
    VAProfile::MilitaryPersonnel::Configuration.instance.breakers_service,
    VAProfile::PersonSettings::Configuration.instance.breakers_service,
    VAProfile::VeteranStatus::Configuration.instance.breakers_service,
    Search::Configuration.instance.breakers_service,
    SearchGsa::Configuration.instance.breakers_service,
    SearchClickTracking::Configuration.instance.breakers_service,
    SOB::DGI::Configuration.instance.breakers_service,
    VAOS::Configuration.instance.breakers_service,
    Vye::DGIB::Configuration.instance.breakers_service,
    IAMSSOeOAuth::Configuration.instance.breakers_service,
    VEText::Configuration.instance.breakers_service,
    PagerDuty::Configuration.instance.breakers_service,
    ClaimsApi::LocalBGS.breakers_service,
    Forms::SubmissionStatuses::PdfUrlVerifier.breakers_service,
    MebApi::DGI::Configuration.instance.breakers_service,
    MebApi::DGI::ContactInfo::Configuration.instance.breakers_service,
    MebApi::DGI::Eligibility::Configuration.instance.breakers_service,
    MebApi::DGI::Status::Configuration.instance.breakers_service,
    MebApi::DGI::Submission::Configuration.instance.breakers_service,
    MebApi::DGI::Automation::Configuration.instance.breakers_service,
    MebApi::DGI::Letters::Configuration.instance.breakers_service,
    UnifiedHealthData::Configuration.instance.breakers_service,
    VHANotification::Configuration.instance.breakers_service,
    MDOT::Configuration.instance.breakers_service,
    Eps::Configuration.instance.breakers_service,
    Ccra::Configuration.instance.breakers_service,
    Apps::Configuration.instance.breakers_service,
    BenefitsIntakeService::Configuration.instance.breakers_service,
    BEP::Awards::Configuration.instance.breakers_service,
    BEP::Claims::Configuration.instance.breakers_service,
    BEP::Persons::Configuration.instance.breakers_service,
    Chip::Configuration.instance.breakers_service,
    ContentionClassification::Configuration.instance.breakers_service,
    DecisionReview::PdfValidation::Configuration.instance.breakers_service,
    DisabilityMaxRatings::Configuration.instance.breakers_service,
    Form526BackupSubmission::Configuration.instance.breakers_service,
    FormIntake::Configuration.instance.breakers_service,
    Forms::Configuration.instance.breakers_service,
    HCA::EnrollmentEligibility::Configuration.instance.breakers_service,
    # Ibm::Configuration.instance.breakers_service,
    Kafka::SchemaRegistry::Configuration.instance.breakers_service,
    LGY::Configuration.instance.breakers_service,
    # Auth::ClientCredentials::Configuration.instance.breakers_service,
    BenefitsClaims::Configuration.instance.breakers_service,
    BenefitsDiscovery::Configuration.instance.breakers_service,
    BenefitsDocuments::Configuration.instance.breakers_service,
    # BenefitsIntake::Configuration.instance.breakers_service,
    BenefitsReferenceData::Configuration.instance.breakers_service,
    BenefitsReferenceData::Staging::Configuration.instance.breakers_service,
    DirectDeposit::Configuration.instance.breakers_service,
    Lighthouse::Facilities::Configuration.instance.breakers_service,
    Lighthouse::HealthcareCostAndCoverage::Configuration.instance.breakers_service,
    # Lighthouse::LettersGenerator::Configuration.instance.breakers_service,
    VeteranVerification::Configuration.instance.breakers_service,
    Lighthouse::VeteransHealth::Configuration.instance.breakers_service,
    MailAutomation::Configuration.instance.breakers_service,
    MAP::SecurityToken::Configuration.instance.breakers_service,
    MAP::SignUp::Configuration.instance.breakers_service,
    BBInternal::Configuration.instance.breakers_service,
    MedicalRecords::Configuration.instance.breakers_service,
    PHRMgr::Configuration.instance.breakers_service,
    UserEligibility::Configuration.instance.breakers_service,
    AAL::Configuration.instance.breakers_service,
    MHV::AccountCreation::Configuration.instance.breakers_service,
    RES::Configuration.instance.breakers_service,
    SignIn::Idme::Configuration.instance.breakers_service,
    SignIn::Logingov::Configuration.instance.breakers_service,
    SSOe::Configuration.instance.breakers_service,
    TokenValidation::V2::Configuration.instance.breakers_service,
    VAProfile::Profile::V3::Configuration.instance.breakers_service,
    VBS::Configuration.instance.breakers_service,
    VeteranEnrollmentSystem::EnrollmentPeriods::Configuration.instance.breakers_service,
    VeteranEnrollmentSystem::Form1095B::Configuration.instance.breakers_service
  ]

  services << CentralMail::Configuration.instance.breakers_service if Settings.central_mail&.upload&.enabled

  plugin = Breakers::StatsdPlugin.new

  client = Breakers::Client.new(
    redis_connection: redis_namespace,
    services:,
    logger: Rails.logger,
    plugins: [plugin]
  )

  # No need to prefix it when using the namespace
  Breakers.redis_prefix = ''
  Breakers.client = client
  Breakers.disabled = true if Settings.breakers_disabled
end
