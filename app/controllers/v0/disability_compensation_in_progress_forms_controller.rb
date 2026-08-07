# frozen_string_literal: true

module V0
  class DisabilityCompensationInProgressFormsController < InProgressFormsController
    include DisabilityCompensation::DisabilityApplicationInteractionTimeLogging

    service_tag 'disability-application'

    def show
      existing_form = form_for_user

      if existing_form
        data = data_and_metadata_with_updated_rated_disabilities
        log_show_existing_form(existing_form, data)
      else
        # create IPF
        data = camelized_prefill_for_user
        log_show_prefill(data)
      end
      render json: data
    end

    def update
      previous_activity_at = read_last_session_activity_at(form_for_user)

      if params[:metadata].present? && parsed_form_data.present?
        if Flipper.enabled?(:disability_compensation_sync_modern0781_flow_metadata)
          params[:metadata][:sync_modern0781_flow] =
            parsed_form_data['sync_modern0781_flow'] || parsed_form_data[:sync_modern0781_flow] || false
        end

        if Flipper.enabled?(:disability_compensation_new_conditions_workflow_metadata)
          params[:metadata][:new_conditions_workflow] =
            parsed_form_data['disability_comp_new_conditions_workflow'] || false
        end
      end
      track_conditions_and_evidence_deltas
      super
      log_form_update(previous_activity_at)
    end

    private

    def parsed_form_data
      @parsed_form_data ||= begin
        form_data = params[:form_data]
        if form_data.present?
          form_data.is_a?(String) ? JSON.parse(form_data) : form_data
        end
      end
    end

    def log_form_update(previous_activity_at = nil)
      updated_form = InProgressForm.form_for_user(form_id, @current_user)
      Rails.logger.info(
        'Form526 InProgressForm update',
        in_progress_form_id: updated_form&.id,
        user_uuid: @current_user&.uuid,
        return_url: params.dig(:metadata, :returnUrl) || params.dig(:metadata, :return_url)
      )
      track_ipf_activity_heartbeat(updated_form&.id, 'update', previous_activity_at:)
      persist_last_session_activity_at!(updated_form)
    end

    def log_show_existing_form(existing_form, data)
      persist_last_session_activity_at!(existing_form)
      log_started_form_version(data, 'get IPF')
      Rails.logger.info('Form526 InProgressForm show',
                        in_progress_form_id: existing_form.id,
                        user_uuid: @current_user&.uuid,
                        return_url: existing_form.metadata&.dig('returnUrl') ||
                          existing_form.metadata&.dig('return_url'))
    end

    def log_show_prefill(data)
      log_started_form_version(data, 'create IPF')
      # next call to #update will create the IPF
      Rails.logger.info(
        'Form526 InProgressForm show (prefill IPF)',
        user_uuid: @current_user&.uuid
      )
      track_prefill_engagement_event
    end

    # Emits a structured log event per user interaction with a Form526 IPF.
    def track_ipf_activity_heartbeat(ipf_id, action, previous_activity_at: nil)
      return if ipf_id.blank?

      log_ipf_active_time_event(
        event_type: action,
        in_progress_form_id: ipf_id,
        terminal: false,
        context: { previous_activity_at: }
      )
    rescue => e
      Rails.logger.warn('Form526 IPF heartbeat event failed', exception: e)
    end

    def track_prefill_engagement_event
      log_ipf_active_time_event(event_type: 'prefill', in_progress_form_id: nil, terminal: false)
    rescue => e
      Rails.logger.warn('Form526 IPF prefill engagement event failed', exception: e)
    end

    # Supporting-evidence array keys in form_data.
    EVIDENCE_KEYS = %w[provider_facility va_treatment_facilities attachments].freeze

    # Top-level formData keys whose presence indicates the user has reached
    # the Supporting Evidence chapter at least once.
    SUPPORTING_EVIDENCE_FORM_DATA_MARKERS = %w[
      view:has_evidence
      view:selectable_evidence_types
    ].freeze

    def reached_supporting_evidence_from_form_data?(form_data)
      return false unless form_data.is_a?(Hash)

      SUPPORTING_EVIDENCE_FORM_DATA_MARKERS.any? { |k| form_data.key?(k) }
    end

    # Compare the pre-update IPF form_data against the incoming form_data to
    # detect condition and supporting-evidence add/remove transitions.
    # Also maintains two per-IPF latches stored in metadata:
    #
    #   had_unpaired_condition_add      — set on condition_added, cleared by
    #                                     a follow-up evidence_added.
    #   had_unpaired_condition_removal  — set on condition_removed, cleared by
    #                                     a follow-up evidence_removed.
    #
    # Evidence additions/removals are tracked only when they can be paired
    # with an unpaired condition event on the same IPF.
    def track_conditions_and_evidence_deltas
      current = normalized_current_form_data
      return unless current.is_a?(Hash)

      previous_ipf = form_for_user
      previous = previous_ipf&.form_data.presence ? JSON.parse(previous_ipf.form_data) : {}
      deltas = compute_conditions_evidence_deltas(previous, current)
      reached_evidence = reached_supporting_evidence_from_form_data?(current)

      latches = {
        add: previous_ipf&.metadata&.dig('had_unpaired_condition_add') == true,
        removal: previous_ipf&.metadata&.dig('had_unpaired_condition_removal') == true
      }
      log_conditions_evidence_events(deltas, latches, previous_ipf&.id) if reached_evidence

      # Always persist latch state regardless of reached_evidence — the parent
      # update! overwrites the full metadata column with params[:metadata], so
      # skipping this on non-evidence PUTs would silently wipe armed latches.
      persist_conditions_evidence_metadata(latches)
    rescue => e
      Rails.logger.error('Form526 evidence/condition delta event failed', exception: e)
    end

    # JSON PUTs deliver form_data as ActionController::Parameters, which is
    # not a Hash. Normalize to a plain Hash so `.key?` / `[]` behave the same
    # regardless of transport.
    def normalized_current_form_data
      current = parsed_form_data
      current.respond_to?(:to_unsafe_h) ? current.to_unsafe_h : current
    end

    def compute_conditions_evidence_deltas(previous, current)
      prev_count = Array(previous['new_disabilities']).length
      curr_count = Array(current['new_disabilities']).length
      {
        condition_added: curr_count > prev_count,
        condition_removed: prev_count > curr_count,
        evidence_added: EVIDENCE_KEYS.any? { |k| Array(current[k]).length > Array(previous[k]).length },
        evidence_removed: EVIDENCE_KEYS.any? { |k| Array(current[k]).length < Array(previous[k]).length }
      }
    end

    # Emits condition/evidence log events and evolves the pairing latches
    # in-place. Evidence events are logged only when they can pair with
    # an unpaired condition event; logging clears the corresponding latch.
    def log_conditions_evidence_events(deltas, latches, ipf_id)
      if deltas[:condition_added]
        log_conditions_evidence_event('condition_added', ipf_id)
        latches[:add] = true
      end

      if deltas[:condition_removed]
        log_conditions_evidence_event('condition_removed', ipf_id)
        latches[:removal] = true
      end

      if deltas[:evidence_added] && latches[:add]
        log_conditions_evidence_event('evidence_added', ipf_id)
        latches[:add] = false
      end

      return unless deltas[:evidence_removed] && latches[:removal]

      log_conditions_evidence_event('evidence_removed', ipf_id)
      latches[:removal] = false
    end

    def log_conditions_evidence_event(event, ipf_id)
      Rails.logger.info(
        'Form526 conditions evidence delta event',
        event:,
        in_progress_form_id: ipf_id,
        user_uuid: @current_user&.uuid,
        form_id: FormProfiles::VA526ez::FORM_ID
      )
    end

    # Persist latch state by mutating params[:metadata] before calling `super`.
    def persist_conditions_evidence_metadata(latches)
      metadata = params[:metadata]
      return if metadata.nil?

      metadata[:had_unpaired_condition_add]     = latches[:add]
      metadata[:had_unpaired_condition_removal] = latches[:removal]
    end

    def form_id
      FormProfiles::VA526ez::FORM_ID
    end

    def data_and_metadata_with_updated_rated_disabilities
      parsed_form_data = JSON.parse(form_for_user.form_data)
      metadata = form_for_user.metadata

      # If the fetched list of rated disabilities does not match our prefilled rated disabilities
      update_rated_disabilities(parsed_form_data, metadata)

      # for Toxic Exposure 1.1 - add indicator to In Progress Forms
      # moving forward, we don't want to change the version if it is already there
      parsed_form_data = set_started_form_version(parsed_form_data)

      # Fix poisoned IPFs: if disabilityCompNewConditionsWorkflow was erroneously
      # injected as true (by useFormFeatureToggleSync) into a form built under the
      # old flow, the user crashes when returnUrl navigates to an old-flow page
      # whose schemas were never initialized (flag true = old-flow pages inactive).
      # Simple fix: if flag is true and returnUrl is an old-flow conditions page,
      # reset the flag to false so old-flow pages activate properly.
      if Flipper.enabled?(:disability_compensation_fix_poisoned_ipf, @current_user)
        parsed_form_data = fix_new_conditions_workflow_flag(parsed_form_data, metadata)
      end

      # purge duplicate additional information properties in IPFs this error only happens for form created
      # between 2/3/2026-2/9/2026 due to the introduction of duplicate additional information key.
      # this function can be removed after a year or when we know all the IPFs created during
      # that time have successfully submitted.
      # TODO: Remove this cleanup block after 2/9/2027 or once all IPFs created between 2/3/2026 and 2/9/2026
      # have successfully submitted.
      if Flipper.enabled?(:disability_compensation_fix_duplicate_key_ipf, @current_user)
        purge_duplicate_additional_information(parsed_form_data)
      end

      {
        formData: parsed_form_data,
        metadata:
      }
    end

    # Old-flow conditions pages — all wrapped by gatePages(workflow, isNewConditionsOff),
    # so they become inactive when the flag is true.
    #   /new-disabilities/follow-up  — showPagePerItem schemas never initialized → RJSF crash
    #   /new-disabilities/add        — depends returns false → redirect loop
    #   /claim-type                  — depends returns false → redirect loop
    #   /disabilities/orientation    — depends returns false → redirect loop
    #   /disabilities/rated-disabilities — depends returns false → redirect loop
    OLD_FLOW_CONDITIONS_PATTERN = %r{
      claim-type |
      disabilities/orientation |
      disabilities/rated-disabilities |
      new-disabilities/(follow-up|add\b)
    }x

    # If the new-conditions-workflow flag is true and returnUrl points to an
    # old-flow conditions page, reset the flag to false. This prevents the
    # RJSF crash (follow-up) and redirect loops (all other old-flow pages).
    WORKFLOW_FLAG_KEY = 'disability_comp_new_conditions_workflow'

    def fix_new_conditions_workflow_flag(form_data, metadata)
      flag = form_data[WORKFLOW_FLAG_KEY]
      return_url = metadata&.dig('returnUrl') || metadata&.dig('return_url') || ''

      return form_data unless [true, 'true'].include?(flag)

      unless OLD_FLOW_CONDITIONS_PATTERN.match?(return_url)
        log_poisoned_ipf_fix('returnUrl not an old-flow conditions page, skipping', flag:, return_url:)
        return form_data
      end

      log_poisoned_ipf_fix('resetting to false — flag true + old-flow returnUrl', flag:, return_url:)
      corrected = form_data.merge(WORKFLOW_FLAG_KEY => false)
      begin
        form_for_user.update!(form_data: corrected.to_json)
      rescue => e
        Rails.logger.error("Form526 fix_poisoned_ipf: failed to persist - #{e.message}")
      end
      corrected
    end

    def log_poisoned_ipf_fix(message, flag: nil, return_url: nil)
      Rails.logger.info("Form526 fix_poisoned_ipf: #{message}",
                        user_uuid: @current_user&.uuid,
                        in_progress_form_id: form_for_user&.id,
                        flag_ipf_value: flag,
                        return_url:)
    end

    def set_started_form_version(data)
      # Only set default if BOTH keys are missing (using && instead of ||)
      if data['started_form_version'].blank? && data['startedFormVersion'].blank?
        log_started_form_version(data, 'existing IPF missing startedFormVersion')
        data['startedFormVersion'] = '2019'
      end
      data
    end

    def rated_disabilities_from_api_provider
      @rated_disabilities_from_api_provider ||=
        FormProfiles::VA526ez.for(form_id:, user: @current_user)
                             .initialize_rated_disabilities_information
    rescue => e
      # if the call fails we skip updating (providers EVSS and LH may have downtime)
      Rails.logger.warn('Form526 IPF failed to fetch rated disabilities', { error: e.class, message: e.message })
      nil
    end

    # Checks whether the rated disabilities in form_data match those returned by an external service.
    # If they differ, assigns the latter to form_data['updatedRatedDisabilities'] and updates the returnUrl
    # to the appropriate page for rated disabilities.
    #
    # Also updates the 'ratedDisabilitiesFetchFailed' flag that may have been set during prefill
    # (in FormProfiles::VA526ez#prefill); if the retry succeeds, the flag is cleared.
    def update_rated_disabilities(form_data, metadata)
      # if the fetch failed, return early; else, clear the flag set during prefill for failed fetches
      if rated_disabilities_from_api_provider.nil?
        return
      else
        form_data.delete('ratedDisabilitiesFetchFailed')
      end

      return if rated_disabilities_from_api_provider.blank? ||
                arr_to_compare(form_data&.dig('ratedDisabilities')) ==
                arr_to_compare(rated_disabilities_from_api_provider&.rated_disabilities&.map(&:attributes))

      if form_data['ratedDisabilities'].present? &&
         form_data.dig('view:claimType', 'view:claimingIncrease')
        return_url = '/disabilities/rated-disabilities'
        # For the new conditions flow, use a different return URL
        return_url = '/conditions/summary' if [true, 'true'].include?(form_data[WORKFLOW_FLAG_KEY])
        metadata['returnUrl'] = return_url
      end
      # Use as_json instead of JSON.parse(to_json) to avoid string allocation overhead
      mapped_rated_disabilities = rated_disabilities_from_api_provider&.rated_disabilities&.map(&:as_json)
      form_data['updatedRatedDisabilities'] = camelize_with_olivebranch(mapped_rated_disabilities)
    end

    def purge_duplicate_additional_information(form_data)
      %w[additionalInformation additional_information].each do |key|
        value = form_data[key]
        form_data.delete(key) unless value.is_a?(String)
      end
    end

    def arr_to_compare(rated_disabilities)
      rated_disabilities&.collect do |rd|
        diagnostic_code = rd['diagnostic_code'] || rd['diagnosticCode']
        rated_disability_id = rd['rated_disability_id'] || rd['ratedDisabilityId']
        "#{diagnostic_code}#{rated_disability_id}#{rd['name']}"
      end&.sort
    end

    # temp: for https://va.ghe.com/software/va.gov-team/issues/97932
    # tracking down a possible issue with prefill
    def log_started_form_version(data, location)
      # Handle different data structures from different call sites:
      # - From show method: {formData: ..., metadata: ...} with symbol keys
      # - From set_started_form_version: raw form data hash with string keys
      form_data = data[:formData] || data['formData'] || data[:form_data] || data['form_data'] || data
      started_form_version = form_data&.dig('startedFormVersion') || form_data&.dig(:startedFormVersion) ||
                             form_data&.dig('started_form_version') || form_data&.dig(:started_form_version)

      if started_form_version.present?
        Rails.logger.info("Form526 InProgressForm startedFormVersion = #{started_form_version} #{location}")
      else
        raise Common::Exceptions::ServiceError.new(
          detail: "no startedFormVersion detected in #{location}",
          source: 'DisabilityCompensationInProgressFormsController#show'
        )
      end
    rescue => e
      Rails.logger.error("Form526 InProgressForm startedFormVersion retrieval failed #{location} #{e.message}")
    end
  end
end
