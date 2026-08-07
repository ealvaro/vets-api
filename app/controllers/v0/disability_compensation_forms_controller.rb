# frozen_string_literal: true

require 'evss/common_service'
require 'evss/disability_compensation_auth_headers'
require 'evss/disability_compensation_form/form4142'
require 'evss/disability_compensation_form/service'
require 'lighthouse/benefits_reference_data/response_strategy'
require 'disability_compensation/factories/api_provider_factory'
require 'disability_compensation/loggers/monitor'

module V0
  class DisabilityCompensationFormsController < ApplicationController
    include RetriableConcern
    include RatedDisabilitiesFetchConcern
    include DisabilityCompensation::DisabilityApplicationInteractionTimeLogging

    service_tag 'disability-application'
    before_action(except: :rating_info) { authorize :evss, :access? }
    before_action(only: :rated_disabilities) { authorize :lighthouse, :access_vet_status? }
    before_action :auth_rating_info, only: [:rating_info]
    before_action :validate_name_part, only: [:suggested_conditions]

    def rated_disabilities
      invoker = 'V0::DisabilityCompensationFormsController#rated_disabilities'
      render json: RatedDisabilitiesSerializer.new(
        fetch_rated_disabilities_response(rated_disabilities_api_provider(@current_user), invoker, @current_user)
      )
    end

    def separation_locations
      response = Lighthouse::ReferenceData::ResponseStrategy.new.cache_by_user_and_type(
        :all_users,
        :get_separation_locations
      ) do
        # A separate provider is needed in order to interact with LH Staging and test BRD e2e properly
        # We use vsp_environment here as RAILS_ENV is set to 'production' in staging
        provider = Settings.vsp_environment == 'staging' ? :lighthouse_staging : :lighthouse
        api_provider = ApiProviderFactory.call(
          type: ApiProviderFactory::FACTORIES[:brd],
          provider:,
          options: {},
          current_user: @current_user,
          feature_toggle: nil
        )
        api_provider.get_separation_locations
      end
      render json: SeparationLocationSerializer.new(response)
    end

    def suggested_conditions
      results = DisabilityContention.suggested(params[:name_part])
      render json: DisabilityContentionSerializer.new(results)
    end

    def add_0781_metadata(form526)
      if form526['syncModern0781Flow'].present?
        { sync_modern0781_flow: form526['syncModern0781Flow'],
          sync_modern0781_flow_answered_online: form526['form0781'].present? }.to_json
      end
    end

    def submit_all_claim
      temp_separation_location_fix if Flipper.enabled?(:disability_compensation_temp_separation_location_code_string,
                                                       @current_user)

      saved_claim = SavedClaim::DisabilityCompensation::Form526AllClaim.from_hash(form_content)
      saved_claim.metadata = check_for_0781_metadata
      in_progress_form = InProgressForm.form_for_user(FormProfiles::VA526ez::FORM_ID, @current_user)
      saved_claim.form_start_date = in_progress_form.created_at if in_progress_form

      saved_claim.save ? log_success(saved_claim) : log_failure(saved_claim, in_progress_form)
      submission = create_submission(saved_claim)
      log_submission(submission, saved_claim, in_progress_form)

      if Flipper.enabled?(:disability_526_toxic_exposure_opt_out_data_purge, @current_user)
        log_toxic_exposure_changes(saved_claim, submission, in_progress_form)
      end

      jid = process_job_submission(submission)
      render json: { data: { attributes: { job_id: jid } } }, status: :ok
    end

    def submission_status
      job_status = Form526JobStatus.where(job_id: params[:job_id]).first
      raise Common::Exceptions::RecordNotFound, params[:job_id] unless job_status

      render json: Form526JobStatusSerializer.new(job_status)
    end

    def rating_info
      render_rating_info
    rescue Common::Exceptions::ExternalServerInternalServerError => e
      monitor.track_request(:warn, 'rating_info upstream error',
                            'api.disability_compensation.rating_info.upstream_error',
                            user_uuid: @current_user&.uuid, error: e.class.to_s)
      raise Common::Exceptions::BadGateway
    rescue Common::Exceptions::BaseError
      raise
    rescue => e
      monitor.track_request(:error, 'rating_info error', 'api.disability_compensation.rating_info.error',
                            user_uuid: @current_user&.uuid, error: e.class.to_s)
      raise
    end

    private

    def render_rating_info
      if lighthouse?
        service = LighthouseRatedDisabilitiesProvider.new(@current_user.icn)
        disability_rating = service.get_combined_disability_rating
        render json: LighthouseRatingInfoSerializer.new({ user_percent_of_disability: disability_rating })
      else
        render json: RatingInfoSerializer.new(EVSS::CommonService.new(auth_headers).get_rating_info)
      end
    end

    def auth_rating_info
      api = lighthouse? ? :lighthouse : :evss
      authorize(api, :rating_info_access?)
    end

    def form_content
      @form_content ||= JSON.parse(request.body.string)
    end

    def lighthouse?
      Flipper.enabled?(:profile_lighthouse_rating_info, @current_user)
    end

    def create_submission(saved_claim)
      Rails.logger.info('Creating 526 submission', user_uuid: @current_user&.uuid, saved_claim_id: saved_claim&.id)
      submission = Form526Submission.new(
        user_uuid: @current_user.uuid,
        user_account: @current_user.user_account,
        saved_claim_id: saved_claim.id,
        auth_headers_json: auth_headers.to_json,
        form_json: saved_claim.to_submission_data(@current_user),
        submit_endpoint: 'claims_api'
      ) { |sub| sub.add_birls_ids @current_user.birls_id }

      if missing_disabilities?(submission)
        raise Common::Exceptions::UnprocessableEntity.new(
          detail: 'no new or increased disabilities were submitted', source: 'DisabilityCompensationFormsController'
        )
      end

      submission.save! && submission
    rescue PG::NotNullViolation => e
      Rails.logger.error(
        'Creating 526 submission: PG::NotNullViolation', user_uuid: @current_user&.uuid, saved_claim_id: saved_claim&.id
      )
      raise e
    end

    def check_for_0781_metadata
      if Flipper.enabled?(:disability_compensation_sync_modern0781_flow_metadata) && form_content['form526'].present?
        add_0781_metadata(form_content['form526'])
      end
    end

    def log_submission(submission, saved_claim, in_progress_form)
      Rails.logger.info(
        'Form526 submit_all_claim',
        in_progress_form_id: in_progress_form&.id,
        saved_claim_id: saved_claim&.id,
        submission_id: submission&.id,
        user_uuid: @current_user&.uuid
      )
      log_active_time(in_progress_form, submission_id: submission&.id)
    end

    def log_active_time(in_progress_form, submission_id: nil)
      return if in_progress_form.blank?

      log_ipf_active_time_event(
        event_type: 'submitted',
        in_progress_form_id: in_progress_form.id,
        terminal: true,
        context: {
          submission_id:,
          previous_activity_at: read_last_session_activity_at(in_progress_form)
        }
      )
    rescue => e
      Rails.logger.warn('Form526 IPF submitted event failed', exception: e)
    end

    def log_failure(claim, in_progress_form)
      if claim&.errors
        monitor.track_saved_claim_save_error(
          # Array of ActiveModel::Error instances from the claim that failed to save
          claim&.errors&.errors,
          in_progress_form&.id,
          @current_user&.uuid
        )
      end

      raise Common::Exceptions::ValidationErrors, claim
    end

    def log_success(claim)
      monitor.track_saved_claim_save_success(
        claim,
        @current_user&.uuid
      )
    end

    def validate_name_part
      raise Common::Exceptions::ParameterMissing, 'name_part' if params[:name_part].blank?
    end

    def auth_headers
      EVSS::DisabilityCompensationAuthHeaders.new(@current_user).add_headers(EVSS::AuthHeaders.new(@current_user).to_h)
    end

    def stats_key
      'api.disability_compensation'
    end

    def missing_disabilities?(submission)
      if submission.form['form526']['form526']['disabilities'].none?
        StatsD.increment("#{stats_key}.failure")
        Rails.logger.error(
          'Creating 526 submission: no new or increased disabilities were submitted', user_uuid: @current_user&.uuid
        )
        return true
      end
      false
    end

    # TEMPORARY
    # Turn separation location into string
    # 11/18/2024 BRD EVSS -> Lighthouse migration caused separation location to turn into an integer,
    # while SavedClaim (vets-json-schema) is expecting a string
    def temp_separation_location_fix
      if form_content.is_a?(Hash) && form_content['form526'].is_a?(Hash)
        separation_location_code = form_content.dig('form526', 'serviceInformation', 'separationLocation',
                                                    'separationLocationCode')
        unless separation_location_code.nil?
          form_content['form526']['serviceInformation']['separationLocation']['separationLocationCode'] =
            separation_location_code.to_s
        end
      end
    end
    # END TEMPORARY

    def monitor
      @monitor ||= DisabilityCompensation::Loggers::Monitor.new
    end

    # Logs toxic exposure data changes during Form 526 submission
    #
    # Compares the user's InProgressForm with the submitted claim to detect
    # when toxic exposure data has been changed or removed by the frontend. This is wrapped
    # in error handling to ensure logging failures do not impact veteran submissions.
    #
    # @param submitted_claim [SavedClaim::DisabilityCompensation::Form526AllClaim] The submitted claim
    # @param submission [Form526Submission] The submission record
    # @param in_progress_form [InProgressForm] The in-progress form record
    # @return [void]
    def log_toxic_exposure_changes(submitted_claim, submission, in_progress_form)
      return unless in_progress_form

      monitor.track_toxic_exposure_changes(
        in_progress_form:,
        submitted_claim:,
        submission:
      )
    rescue => e
      # Don't fail submission if logging fails
      Rails.logger.error(
        'Error logging toxic exposure changes',
        user_uuid: @current_user&.uuid,
        saved_claim_id: submitted_claim&.id,
        submission_id: submission&.id,
        error: e.message,
        backtrace: e.backtrace&.first(5)
      )
    end

    def process_job_submission(submission)
      # Feature flag to stop submission from being submitted to Lighthouse and onto VBMS
      if Flipper.enabled?(:disability_compensation_prevent_submission_job, @current_user)
        Rails.logger.info("Submission ID: #{submission.id} prevented from sending to third party service.")
        # if jid = 0 then the submission was prevented from going any further in the process
        0
      else
        submission.start
      end
    end
  end
end
