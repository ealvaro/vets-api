# frozen_string_literal: true

require 'benefits_claims/title_generator'
require 'lighthouse/benefits_claims/service'
require 'lighthouse/benefits_claims/constants'
require 'lighthouse/benefits_claims/tracked_item_content'
require 'lighthouse/benefits_documents/constants'
require 'lighthouse/benefits_claims/utilities/helpers'
require 'lighthouse/benefits_documents/documents_status_polling_service'
require 'lighthouse/benefits_documents/update_documents_status_service'

module V0
  # rubocop:disable Metrics/ClassLength
  class BenefitsClaimsController < ApplicationController
    include InboundRequestLogging
    include V0::Concerns::MultiProviderSupport
    before_action { authorize :lighthouse, :access? }
    before_action :log_request_origin
    service_tag 'claims-shared'

    STATSD_METRIC_PREFIX = 'api.benefits_claims'
    STATSD_TAGS = [
      'service:benefits-claims',
      'team:cross-benefits-crew',
      'team:benefits',
      'itportfolio:benefits-delivery',
      'dependency:lighthouse'
    ].freeze

    FEATURE_USE_TITLE_GENERATOR_WEB = 'cst_use_claim_title_generator_web'
    FEATURE_MULTI_CLAIM_PROVIDER = 'cst_multi_claim_provider'
    FEATURE_CHAMPVA_DOCS_ONLY_RESUBMISSION = 'benefits_documents_ivc_champva_docs_only_resubmission'
    DEFAULT_UPLOAD_DESTINATION_KEY = 'benefits_claims'
    IVC_CHAMPVA_UPLOAD_DESTINATION_KEY = 'ivc_champva_supporting_documents'
    IVC_CHAMPVA_FINALIZE_DESTINATION_KEY = 'ivc_champva_docs_only_resubmission'

    UPLOAD_DESTINATION_KEY_BY_PROVIDER = {
      'lighthouse' => DEFAULT_UPLOAD_DESTINATION_KEY,
      'ivc_champva' => IVC_CHAMPVA_UPLOAD_DESTINATION_KEY
    }.freeze

    IVC_CHAMPVA_FORM_ID_BY_CLAIM_TYPE = {
      'CHAMPVA application' => '10-10D-EXTENDED',
      'Other Health Insurance' => '10-7959C',
      'Foreign Medical Program registration' => '10-7959F-1',
      'Foreign Medical Program claim' => '10-7959F-2',
      'CHAMPVA claim' => '10-7959A'
    }.freeze

    IVC_CHAMPVA_10_10D_EXTENDED_DOCUMENT_TYPE_OPTIONS = [
      'Annulment decree',
      'Birth certificate',
      'Certificate of civil union',
      'Common-law marriage affidavit',
      'Court-ordered adoption papers',
      'Death certificate',
      'Disability rating letter for the child',
      'Divorce decree',
      'Marriage certificate',
      'School acceptance letter',
      'School enrollment certification letter',
      'Social Security card'
    ].map { |option| { 'value' => option, 'label' => option } }.freeze

    IVC_CHAMPVA_DOCUMENT_TYPE_OPTIONS_BY_FORM_ID = {
      '10-10D-EXTENDED' => IVC_CHAMPVA_10_10D_EXTENDED_DOCUMENT_TYPE_OPTIONS,
      '10-10D-SUPPLEMENTAL' => IVC_CHAMPVA_10_10D_EXTENDED_DOCUMENT_TYPE_OPTIONS,
      '10-10D-SUPPLEMENTAL-EXISTING' => IVC_CHAMPVA_10_10D_EXTENDED_DOCUMENT_TYPE_OPTIONS,
      '10-10D-SUPPLEMENTAL-ENROLLMENT' => IVC_CHAMPVA_10_10D_EXTENDED_DOCUMENT_TYPE_OPTIONS
    }.freeze

    IVC_CHAMPVA_ACCEPTED_FILE_TYPES = %w[pdf jpg jpeg png].freeze

    LIGHTHOUSE_DOCUMENT_UPLOAD_JOB_CLASS = Lighthouse::EvidenceSubmissions::DocumentUpload.name

    def index
      claims = if Flipper.enabled?(FEATURE_MULTI_CLAIM_PROVIDER, @current_user)
                 get_claims_from_providers
               else
                 service.get_claims
               end
      claims_data = claims['data']

      check_for_birls_id
      check_for_file_number

      prepare_index_claims(claims_data)

      claim_ids = claims_data.map { |claim| claim['id'] }
      evidence_submissions = fetch_evidence_submissions(claim_ids, 'index')

      add_evidence_submissions_to_claims(claims_data, evidence_submissions, 'index')

      tap_claims(claims_data)

      report_evidence_submission_metrics('index', evidence_submissions)

      render json: claims
    end

    def show
      claim = if Flipper.enabled?(FEATURE_MULTI_CLAIM_PROVIDER, @current_user)
                # Multi-provider path: Lighthouse-specific transforms applied in V0::LighthouseClaims::Proxy
                get_claim_from_providers(params[:id], params[:type])
              else
                # Legacy single-provider path: Apply Lighthouse-specific transforms here
                get_legacy_claim(params[:id])
              end
      claim_data = claim['data']
      champva_cst_file_uploader_docs_only_resubmission_enabled =
        champva_cst_file_uploader_docs_only_resubmission_enabled?
      title_generator_enabled = title_generator_enabled?
      update_claim_type_language(claim_data, title_generator_enabled:)
      add_upload_metadata(claim_data, champva_cst_file_uploader_docs_only_resubmission_enabled:)

      # Document uploads to EVSS require a birls_id; This restriction should
      # be removed when we move to Lighthouse Benefits Documents for document uploads
      claim_data['attributes']['canUpload'] = !@current_user.birls_id.nil?

      evidence_submissions = fetch_evidence_submissions(claim_data['id'], 'show')

      update_evidence_submissions_for_claim(claim_data['id'], evidence_submissions)
      add_evidence_submissions_to_claims([claim_data], evidence_submissions, 'show')

      # We want to log some details about claim type patterns to track in DataDog
      log_show_claim_details(claim_data, params[:id], title_generator_enabled:)

      tap_claims([claim_data])

      report_evidence_submission_metrics('show', evidence_submissions)

      render json: claim
    end

    def submit5103
      # Log if the user doesn't have a file number
      # NOTE: We are treating the BIRLS ID as a substitute
      # for file number here
      ::Rails.logger.info('[5103 Submission] No file number') if @current_user.birls_id.nil?

      json_payload = request.body.read

      data = JSON.parse(json_payload)

      tracked_item_id = data['trackedItemId'] || nil

      res = service.submit5103(params[:id], tracked_item_id)

      render json: res
    end

    def failed_upload_evidence_submissions
      render json: { data: filter_failed_evidence_submissions }
    end

    private

    def log_request_origin
      return unless Flipper.enabled?(:log_claims_request_origin)

      log_inbound_request(message_type: 'lh.cst.inbound_request', message: 'Inbound request (Lighthouse claim status)')
    end

    def failed_evidence_submissions
      @failed_evidence_submissions ||= EvidenceSubmission.failed.where(user_account: current_user_account.id)
    end

    def current_user_account
      UserAccount.find(@current_user.user_account_uuid)
    end

    def claims_scope
      EVSSClaim.for_user(@current_user)
    end

    def service
      @service ||= BenefitsClaims::Service.new(
        @current_user,
        classify_tracked_items_by_list: classify_tracked_items_by_list?
      )
    end

    def check_for_birls_id
      ::Rails.logger.info('[BenefitsClaims#index] No birls id') if current_user.birls_id.nil?
    end

    def check_for_file_number
      bgs_file_number = BGS::People::Request.new.find_person_by_participant_id(user: current_user).file_number
      ::Rails.logger.info('[BenefitsClaims#index] No file number') if bgs_file_number.blank?
    end

    def get_legacy_claim(claim_id)
      legacy_claim = service.get_claim(claim_id)
      if Flipper.enabled?(:cst_suppress_evidence_requests_website)
        legacy_claim = suppress_evidence_requests(legacy_claim)
      end
      legacy_claim
    end

    def prepare_index_claims(claims)
      champva_cst_file_uploader_docs_only_resubmission_enabled =
        champva_cst_file_uploader_docs_only_resubmission_enabled?
      title_generator_enabled = title_generator_enabled?
      multi_claim_provider_enabled = Flipper.enabled?(FEATURE_MULTI_CLAIM_PROVIDER, @current_user)

      claims.each do |claim|
        update_claim_type_language(claim, title_generator_enabled:)
        add_upload_metadata(claim, champva_cst_file_uploader_docs_only_resubmission_enabled:)
        log_claim_type_details(claim['attributes'], claim['id'], source: 'index',
                                                                 title_generator_enabled:,
                                                                 multi_claim_provider_enabled:)
      end
    end

    def tap_claims(claims)
      claims.each do |claim|
        record = claims_scope.where(evss_id: claim['id']).first

        if record.blank?
          EVSSClaim.create(
            user_uuid: @current_user.uuid,
            user_account: @current_user.user_account,
            evss_id: claim['id'],
            data: {}
          )
        else
          # If there is a record, we want to set the updated_at field
          # to Time.zone.now
          record.touch # rubocop:disable Rails/SkipsModelValidations
        end
      end
    end

    def update_claim_type_language(claim, title_generator_enabled:)
      if title_generator_enabled
        # Adds displayTitle and claimTypeBase to the claim response object
        BenefitsClaims::TitleGenerator.update_claim_title(claim)
      end

      # always map "Death" claimType to "expenses related to death or burial"
      # TODO: #131812 [CST/MyVA] Remove claimType mapping from api responses (blocked)
      language_map = BenefitsClaims::Constants::CLAIM_TYPE_LANGUAGE_MAP
      if language_map.key?(claim.dig('attributes', 'claimType'))
        claim['attributes']['claimType'] = language_map[claim['attributes']['claimType']]
      end
    end

    def add_upload_metadata(claim, champva_cst_file_uploader_docs_only_resubmission_enabled: false)
      metadata = build_upload_metadata_for_claim(
        claim,
        champva_cst_file_uploader_docs_only_resubmission_enabled:
      )
      return if metadata.blank?

      claim['attributes'] ||= {}
      claim['attributes']['uploadMetadata'] = metadata
    end

    def build_upload_metadata_for_claim(claim, champva_cst_file_uploader_docs_only_resubmission_enabled: false)
      claim_attributes = claim['attributes'] || {}
      provider = claim_attributes['provider'].presence
      destination_key = UPLOAD_DESTINATION_KEY_BY_PROVIDER.fetch(provider, DEFAULT_UPLOAD_DESTINATION_KEY)

      metadata = { 'uploadDestinationKey' => destination_key }

      if destination_key == IVC_CHAMPVA_UPLOAD_DESTINATION_KEY
        form_id = IVC_CHAMPVA_FORM_ID_BY_CLAIM_TYPE[claim_attributes['claimType']]
        metadata['formId'] = form_id if form_id.present?
        metadata['acceptedFileTypes'] = IVC_CHAMPVA_ACCEPTED_FILE_TYPES
        if form_id == '10-10D-EXTENDED' && champva_cst_file_uploader_docs_only_resubmission_enabled
          metadata['finalizeDestinationKey'] = IVC_CHAMPVA_FINALIZE_DESTINATION_KEY
          metadata['submissionType'] = 'existing'
        end

        document_type_options = IVC_CHAMPVA_DOCUMENT_TYPE_OPTIONS_BY_FORM_ID[form_id]
        metadata['documentTypeOptions'] = document_type_options if document_type_options.present?
      end

      metadata
    end

    def champva_cst_file_uploader_docs_only_resubmission_enabled?
      Flipper.enabled?(:champva_cst_file_uploader_docs_only_resubmission, @current_user)
    end

    def title_generator_enabled?
      Flipper.enabled?(FEATURE_USE_TITLE_GENERATOR_WEB)
    end

    def classify_tracked_items_by_list?
      Flipper.enabled?(:cst_surface_closed_tracked_items, @current_user)
    end

    def add_evidence_submissions(claim, evidence_submissions)
      displayable = filter_evidence_submissions_for_display(evidence_submissions)
      tracked_items = claim['attributes']['trackedItems']
      displayable.map { |es| build_filtered_evidence_submission_record(es, tracked_items) }
    end

    # Lighthouse uploads surface via supportingDocuments once VBMS ingests them. Returning the
    # corresponding SUCCESS EvidenceSubmission rows here would render the same file twice on the
    # "Files received" tab (often as foo.jpg + foo.pdf because VBMS converts images). CHAMPVA
    # uploads never produce a supportingDocument, so they're the only path that still needs this
    # rendering. In-flight Lighthouse rows (CREATED/QUEUED/PENDING/FAILED) still flow through so
    # they can power the in-progress and failed-upload UIs.
    def filter_evidence_submissions_for_display(evidence_submissions)
      evidence_submissions.reject do |es|
        es.completed? && es.job_class == LIGHTHOUSE_DOCUMENT_UPLOAD_JOB_CLASS
      end
    end

    def filter_failed_evidence_submissions
      filtered_evidence_submissions = []
      claims = {}

      failed_evidence_submissions.each do |es|
        # When we get a claim we add it to claims so that we prevent calling lighthouse multiple times
        # to get the same claim.
        claim = claims[es.claim_id]

        if claim.nil?
          claim = service.get_claim(es.claim_id)
          claims[es.claim_id] = claim
        end

        tracked_items = claim['data']['attributes']['trackedItems']

        filtered_evidence_submissions.push(build_filtered_evidence_submission_record(es, tracked_items))
      end

      filtered_evidence_submissions
    end

    def build_filtered_evidence_submission_record(evidence_submission, tracked_items) # rubocop:disable Metrics/MethodLength
      personalisation = JSON.parse(evidence_submission.template_metadata)['personalisation']
      tracked_item_display_name = BenefitsClaims::Utilities::Helpers.get_tracked_item_display_name(
        evidence_submission.tracked_item_id,
        tracked_items
      )
      tracked_item_friendly_name = BenefitsClaims::TrackedItemContent.find_by_display_name(tracked_item_display_name) # rubocop:disable Rails/DynamicFindBy
                                                                     &.dig(:friendlyName)

      { acknowledgement_date: evidence_submission.acknowledgement_date,
        claim_id: evidence_submission.claim_id,
        created_at: evidence_submission.created_at,
        delete_date: evidence_submission.delete_date,
        document_type: personalisation['document_type'],
        failed_date: evidence_submission.failed_date,
        file_name: personalisation['file_name'],
        id: evidence_submission.id,
        lighthouse_upload: evidence_submission.job_class == LIGHTHOUSE_DOCUMENT_UPLOAD_JOB_CLASS,
        tracked_item_id: evidence_submission.tracked_item_id,
        tracked_item_display_name:,
        tracked_item_friendly_name:,
        upload_status: evidence_submission.upload_status,
        va_notify_status: evidence_submission.va_notify_status }
    end

    def log_show_claim_details(claim_data, requested_claim_id, title_generator_enabled:)
      log_claim_type_details(
        claim_data['attributes'], requested_claim_id,
        source: 'show',
        title_generator_enabled:,
        multi_claim_provider_enabled: Flipper.enabled?(FEATURE_MULTI_CLAIM_PROVIDER, @current_user)
      )
      log_evidence_requests(requested_claim_id, claim_data['attributes'])
    end

    def log_claim_type_details(claim_info, claim_id, source:, title_generator_enabled:,
                               multi_claim_provider_enabled:)
      # `provider` is nil in two cases and `multi_claim_provider_enabled` tells them apart: with the
      # flag off nothing stamps it, with the flag on a nil means a provider failed to label its claims.
      payload = {
        message_type: 'lh.cst.claim_types',
        source:,
        provider: claim_info['provider'],
        multi_claim_provider_enabled:,
        claim_type: claim_info['claimType'],
        claim_type_code: claim_info['claimTypeCode'],
        claim_date: claim_info['claimDate'],
        ep_code: claim_info['endProductCode'],
        decision_letter_sent: claim_info['decisionLetterSent'],
        development_letter_sent: claim_info['developmentLetterSent'],
        display_title: claim_info['displayTitle'],
        claim_type_base: claim_info['claimTypeBase'],
        title_generator_enabled:,
        claim_id:
      }

      payload.merge!(claim_detail_only_fields(claim_info)) if source == 'show'

      ::Rails.logger.info('Claim Type Details', payload)
    end

    # Absent from the list response, which has no `contentions` and exposes only `phaseChangeDate`.
    def claim_detail_only_fields(claim_info)
      {
        num_contentions: claim_info['contentions']&.count,
        current_phase_back: claim_info.dig('claimPhaseDates', 'currentPhaseBack'),
        latest_phase_type: claim_info.dig('claimPhaseDates', 'latestPhaseType')
      }
    end

    def log_evidence_requests(claim_id, claim_info)
      tracked_items = claim_info['trackedItems']
      return if tracked_items.blank?

      # Logged alongside the value so a nil `is_first_party` can be told apart: with the flag off it
      # is simply not set, but with the flag on it means the field was lost in transit.
      # Read once here rather than in the loop below, which would cost one flag lookup per item.
      classify_by_evidence_list = classify_tracked_items_by_list?

      tracked_items.each do |ti|
        ::Rails.logger.info('Evidence Request Types',
                            { message_type: 'lh.cst.evidence_requests',
                              claim_id:,
                              tracked_item_id: ti['id'],
                              tracked_item_type: ti['displayName'],
                              tracked_item_status: ti['status'],
                              suspense_date: ti['suspenseDate'],
                              classify_by_evidence_list:,
                              tracked_item_is_first_party: ti['isFirstParty'] })
      end
    end

    def suppress_evidence_requests(claim)
      tracked_items = claim.dig('data', 'attributes', 'trackedItems')
      return unless tracked_items

      tracked_items.reject! { |i| BenefitsClaims::Constants::SUPPRESSED_EVIDENCE_REQUESTS.include?(i['displayName']) }
      claim
    end

    def report_evidence_submission_metrics(endpoint, evidence_submissions)
      status_counts = evidence_submissions.group(:upload_status).count

      BenefitsDocuments::Constants::UPLOAD_STATUS.each_value do |status|
        count = status_counts[status] || 0
        next if count.zero?

        StatsD.increment("#{STATSD_METRIC_PREFIX}.#{endpoint}", count, tags: STATSD_TAGS + ["status:#{status}"])
      end
    rescue => e
      ::Rails.logger.error(
        "BenefitsClaimsController##{endpoint} Error reporting evidence submission upload status metrics: #{e.message}"
      )
    end

    def fetch_evidence_submissions(claim_ids, endpoint)
      query_ids = resolve_evidence_submission_claim_ids(claim_ids)
      return EvidenceSubmission.none if query_ids.empty?

      EvidenceSubmission.where(claim_id: query_ids)
    rescue => e
      ::Rails.logger.error(
        "BenefitsClaimsController##{endpoint} Error fetching evidence submissions",
        {
          claim_ids: Array(claim_ids),
          error_message: e.message,
          error_class: e.class.name,
          timestamp: Time.now.utc
        }
      )
      EvidenceSubmission.none
    end

    def resolve_evidence_submission_claim_ids(claim_ids)
      identifiers = Array(claim_ids).compact.map(&:to_s)
      return [] if identifiers.empty?

      numeric_ids = identifiers.grep(/\A\d+\z/).map(&:to_i)
      uuid_ids = identifiers.grep_v(/\A\d+\z/)
      numeric_ids += IvcChampvaForm.where(form_uuid: uuid_ids).pluck(:id) if uuid_ids.any?

      numeric_ids.uniq
    end

    def update_evidence_submissions_for_claim(claim_id, evidence_submissions)
      # Get pending evidence submissions as an ActiveRecord relation
      # PENDING = successfully sent to Lighthouse with request_id, awaiting final status
      # Note: We chain scopes on the provided relation because UpdateDocumentsStatusService
      # requires an ActiveRecord::Relation with find_by! method (not an Array)
      pending_submissions = evidence_submissions.where(
        upload_status: BenefitsDocuments::Constants::UPLOAD_STATUS[:PENDING]
      ).where.not(request_id: nil)

      unless pending_submissions.empty?
        request_ids = pending_submissions.pluck(:request_id)

        # Check if we recently polled for the same request_ids (cache hit)
        if recently_polled_request_ids?(claim_id, request_ids)
          StatsD.increment("#{STATSD_METRIC_PREFIX}.show.evidence_submission_cache_hit", tags: STATSD_TAGS)
          return
        end

        # Cache miss - proceed with polling
        StatsD.increment("#{STATSD_METRIC_PREFIX}.show.evidence_submission_cache_miss", tags: STATSD_TAGS)
        process_evidence_submissions(claim_id, pending_submissions, request_ids)
      end
    end

    def process_evidence_submissions(claim_id, pending_submissions, request_ids)
      poll_response = poll_lighthouse_for_status(claim_id, request_ids)
      return unless poll_response

      process_status_update(claim_id, pending_submissions, poll_response, request_ids)
    end

    def poll_lighthouse_for_status(claim_id, request_ids)
      # Call the same polling service used by the hourly job
      poll_response = BenefitsDocuments::DocumentsStatusPollingService.call(request_ids)

      # Validate successful response with expected data structure
      if poll_response.status == 200
        if poll_response.body&.dig('data', 'statuses').blank?
          # Handle case where Lighthouse response doesn't have statuses
          error_response = OpenStruct.new(status: 200, body: poll_response.body)
          handle_error(claim_id, error_response, request_ids, 'polling')
          return nil
        end

        poll_response
      else
        # Log non-200 responses
        handle_error(claim_id, poll_response, request_ids, 'polling')
      end
    rescue => e
      # Catch unexpected exceptions from polling service (network errors, timeouts, etc.)
      error_response = OpenStruct.new(status: nil, body: e.message)
      handle_error(claim_id, error_response, request_ids, 'polling')
    end

    def process_status_update(claim_id, pending_submissions, poll_response, request_ids)
      update_result = BenefitsDocuments::UpdateDocumentsStatusService.call(
        pending_submissions,
        poll_response.body
      )

      # Handle case where update service found unknown request IDs
      if update_result && !update_result[:success]
        response_struct = OpenStruct.new(update_result[:response])
        handle_error(claim_id, response_struct, response_struct.unknown_ids.map(&:to_s), 'update')
      else
        # Log success metric when polling and update complete successfully
        StatsD.increment("#{STATSD_METRIC_PREFIX}.show.upload_status_success", tags: STATSD_TAGS)
        # Cache the polled request_ids to prevent redundant polling within TTL window
        cache_polled_request_ids(claim_id, request_ids)
      end
    rescue => e
      # Catch unexpected exceptions from update operations
      # Log error but don't fail the request - graceful degradation
      error_response = OpenStruct.new(status: 200, body: e.message)
      handle_error(claim_id, error_response, request_ids, 'update')
    end

    def handle_error(claim_id, response, lighthouse_document_request_ids, error_source)
      ::Rails.logger.error(
        'BenefitsClaimsController#show Error polling evidence submissions',
        {
          claim_id:,
          error_source:,
          response_status: response.status,
          response_body: response.body,
          lighthouse_document_request_ids:,
          timestamp: Time.now.utc
        }
      )
      StatsD.increment(
        "#{STATSD_METRIC_PREFIX}.show.upload_status_error",
        tags: STATSD_TAGS + ["error_source:#{error_source}"]
      )
    end

    def add_evidence_submissions_to_claims(claims, all_evidence_submissions, endpoint)
      return if claims.empty?

      evidence_submissions_by_claim_id = all_evidence_submissions.group_by(&:claim_id)
      ivc_form_ids_by_uuid = {}

      assign_evidence_submissions_to_claims(
        claims,
        evidence_submissions_by_claim_id,
        ivc_form_ids_by_uuid
      )
    rescue ArgumentError
      ensure_claims_have_evidence_submissions(claims)
    rescue => e
      log_add_evidence_submissions_error(claims, endpoint, e)
    end

    def assign_evidence_submissions_to_claims(claims, evidence_submissions_by_claim_id, ivc_form_ids_by_uuid)
      claims.each do |claim|
        evidence_submissions = evidence_submissions_for_claim(
          claim,
          evidence_submissions_by_claim_id,
          ivc_form_ids_by_uuid
        )
        claim['attributes']['evidenceSubmissions'] =
          add_evidence_submissions(claim, evidence_submissions)
      end
    end

    def ensure_claims_have_evidence_submissions(claims)
      claims.each do |claim|
        claim['attributes']['evidenceSubmissions'] ||= []
      end
    end

    def log_add_evidence_submissions_error(claims, endpoint, error)
      claim_ids = claims.map { |claim| claim['id'] }
      ::Rails.logger.error(
        "BenefitsClaimsController##{endpoint} Error adding evidence submissions",
        { claim_ids:, error_class: error.class.name }
      )
    end

    def evidence_submissions_for_claim(claim, evidence_submissions_by_claim_id, ivc_form_ids_by_uuid)
      provider = claim.dig('attributes', 'provider')
      claim_id = claim['id'].to_s
      return non_champva_evidence_submissions(claim_id, evidence_submissions_by_claim_id) if provider != 'ivc_champva'

      ivc_form_ids_by_uuid[claim_id] ||= IvcChampvaForm.where(form_uuid: claim_id).pluck(:id)
      ivc_form_ids_by_uuid[claim_id].flat_map { |form_id| evidence_submissions_by_claim_id[form_id] || [] }
    end

    def non_champva_evidence_submissions(claim_id, evidence_submissions_by_claim_id)
      numeric_claim_id = Integer(claim_id, 10)
      evidence_submissions_by_claim_id[numeric_claim_id] || []
    end

    def recently_polled_request_ids?(claim_id, request_ids)
      cache_record = EvidenceSubmissionPollStore.find(claim_id.to_s)
      return false if cache_record.nil?

      cache_record.request_ids.sort == request_ids.sort
    rescue => e
      ::Rails.logger.error(
        'BenefitsClaimsController#show Error reading evidence submission poll cache',
        {
          claim_id:,
          request_ids:,
          error_class: e.class.name,
          error_message: e.message
        }
      )
      false
    end

    def cache_polled_request_ids(claim_id, request_ids)
      EvidenceSubmissionPollStore.create(
        claim_id: claim_id.to_s,
        request_ids:
      )
    rescue => e
      ::Rails.logger.error(
        'BenefitsClaimsController#show Error writing evidence submission poll cache',
        {
          claim_id:,
          request_ids:,
          error_class: e.class.name,
          error_message: e.message
        }
      )
    end
  end
  # rubocop:enable Metrics/ClassLength
end
