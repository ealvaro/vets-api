# frozen_string_literal: true

module AccreditedRepresentativePortal
  module PowerOfAttorneyRequestService
    class Accept
      class Error < RuntimeError
        attr_reader :status

        def initialize(message, status)
          @status = status
          super(message)
        end
      end

      TRANSIENT_ERROR_TYPES =
        BenefitsClaims::ServiceException::ERROR_MAP.select do |key, _|
          [429, 500, 502, 503, 504].include? key
        end.values.freeze
      FATAL_ERROR_TYPES =
        BenefitsClaims::ServiceException::ERROR_MAP.select do |key, _|
          [400, 401, 403, 404, 413, 422].include? key
        end.values.freeze

      attr_reader :poa_request, :creator_id, :resolution, :form_data

      def initialize(poa_request, creator_id, power_of_attorney_holder_memberships)
        @poa_request = poa_request
        @form_data = poa_request.power_of_attorney_form.parsed_data
        @creator_id = creator_id
        @resolution = nil
        @power_of_attorney_holder_memberships =
          power_of_attorney_holder_memberships
      end

      def call
        # Step 1: commit the acceptance row on its own, short-lived transaction.
        # This is where the unique-index lock on power_of_attorney_request_id
        # is taken. Committing immediately means any concurrent Accept attempt
        # for the same request fails fast with RecordNotUnique (or, under
        # contention, LockWaitTimeout) instead of queuing behind an open
        # transaction for the duration of the Lighthouse call below.
        @resolution = create_acceptance

        # Step 2: everything from here on is outside the DB transaction that
        # held the lock. A slow or failing Lighthouse call can no longer make
        # other requests wait on this row.
        response = submit_form
        form_submission = create_form_submission!(response.body)
        enqueue_form_processing(form_submission)
        form_submission
      rescue Common::Exceptions::ResourceNotFound => e
        handle_resource_not_found(e)
      rescue ActiveRecord::RecordInvalid => e
        handle_record_invalid(e)
      rescue ActiveRecord::RecordNotUnique, ActiveRecord::LockWaitTimeout => e
        handle_already_resolved(e)
      rescue *TRANSIENT_ERROR_TYPES, Faraday::TimeoutError => e
        handle_transient_error(e)
      rescue *FATAL_ERROR_TYPES => e
        handle_fatal_error(e)
      rescue => e
        handle_unexpected_error(e)
      end

      private

      def create_acceptance
        PowerOfAttorneyRequestDecision.create_acceptance!(
          creator_id:,
          power_of_attorney_holder_memberships:
            @power_of_attorney_holder_memberships,
          power_of_attorney_request: poa_request
        )
      end

      def submit_form
        service.submit2122(form_payload)
      end

      def enqueue_form_processing(form_submission)
        PowerOfAttorneyFormSubmissionJob.perform_async(form_submission.id)
      end

      def handle_resource_not_found(error)
        error_message = error.try(:detail) || error.message
        Rails.logger.error("[AR::POA] resource_not_found message=#{error_message}")
        raise Error.new(error_message, :not_found)
      end

      def handle_record_invalid(error)
        raise Error.new(error.message, :bad_request)
      end

      def handle_already_resolved(_error)
        Rails.logger.info("[AR::POA] already_resolved poa_request_id=#{poa_request.id}")
        raise Error.new('This power of attorney request has already been resolved', :conflict)
      end

      def handle_transient_error(error)
        raise Error.new(error.message, :gateway_timeout)
      end

      def handle_fatal_error(error)
        error_message = error.respond_to?(:detail) ? error.detail : error.message
        log_enqueue_failure(error, error_message)
        # @resolution is already committed at this point (Step 1 above), so
        # this error form submission correctly records a failure against a
        # real, persisted acceptance rather than one that might roll back.
        create_error_form_submission(error_message, {})
        raise Error.new(error_message, :not_found)
      end

      def handle_unexpected_error(error)
        Rails.logger.error("Unexpected error in Accept#call: #{error.class} - #{error.message}")
        Rails.logger.error(error.backtrace.join("\n")) if error.backtrace
        # Only meaningful if create_acceptance already succeeded; if it
        # raised, @resolution is nil and poa_request association is still
        # valid, so this call is safe either way.
        create_error_form_submission(error.message, {})
        raise
      end

      def service
        @service ||= BenefitsClaims::Service.new(veteran_icn)
      end

      def dependent_claimant?
        poa_request.claimant_type == PowerOfAttorneyRequest::ClaimantTypes::DEPENDENT
      end

      def veteran_icn
        if Flipper.enabled?(:form2122_non_veteran_digital_submit) && dependent_claimant?
          veteran_data = {
            first_name: form_data.dig('veteran', 'name', 'first'),
            last_name: form_data.dig('veteran', 'name', 'last'),
            ssn: form_data.dig('veteran', 'ssn'),
            birth_date: form_data.dig('veteran', 'dateOfBirth')
          }
          @veteran_icn ||= ClaimantLookupService.get_icn(
            veteran_data[:first_name],
            veteran_data[:last_name],
            veteran_data[:ssn],
            veteran_data[:birth_date]
          )
        else
          @veteran_icn ||= claimant_icn
        end
      end

      def claimant_icn
        poa_request.claimant.icn
      end

      def create_form_submission!(response_body)
        PowerOfAttorneyFormSubmission.create!(
          power_of_attorney_request: poa_request,
          service_id: response_body.dig('data', 'id'),
          service_response: response_body.to_json,
          status: :enqueue_succeeded,
          status_updated_at: DateTime.current
        )
      end

      def create_error_form_submission(message, response_body)
        PowerOfAttorneyFormSubmission.create(
          power_of_attorney_request: poa_request,
          status: :enqueue_failed,
          status_updated_at: DateTime.current,
          service_response: response_body.is_a?(String) ? response_body : response_body.to_json,
          error_message: message
        )

        Monitoring.new.track_duration('ar.poa.submission.enqueue_failed.duration', from: @poa_request.created_at)
      end

      def log_enqueue_failure(error, error_message)
        status_code = error.respond_to?(:status_code) ? error.status_code : nil
        error_details = extract_error_details(error)

        Monitoring.new.track_count(
          'ar.poa.submission.enqueue_failed.count',
          tags: [
            "error_class:#{error.class.name}",
            ("status:#{status_code}" if status_code)
          ].compact
        )

        Rails.logger.error(
          [
            '[AR::POA] enqueue_failed',
            "poa_request_id=#{poa_request.id}",
            "poa_code=#{poa_request.power_of_attorney_holder_poa_code}",
            ("status=#{status_code}" if status_code),
            "error_class=#{error.class.name}",
            "message=#{error_message}",
            ("errors=#{error_details.to_json}" if error_details.present?)
          ].compact.join(' ')
        )
      end

      def extract_error_details(error)
        return unless error.respond_to?(:errors)

        Array(error.errors).map do |err|
          if err.respond_to?(:to_hash)
            err.to_hash.slice(:code, :detail, :title, :status)
          elsif err.is_a?(Hash)
            err.slice(:code, :detail, :title, :status)
          else
            { detail: err.to_s }
          end
        end.compact.presence
      end

      def form_payload
        {}.tap do |a|
          a[:veteran] = veteran_data
          a[:claimant] = claimant_data if Flipper.enabled?(:form2122_non_veteran_digital_submit) && dependent_claimant?
          a[:serviceOrganization] = organization_data
          a[:recordConsent] = form_data.dig('authorizations', 'recordDisclosureLimitations').blank?
          a[:consentLimits] = form_data.dig('authorizations', 'recordDisclosureLimitations') || []
          a[:consentAddressChange] = form_data.dig('authorizations', 'addressChange') == true

          if Flipper.enabled?(:form2122_non_veteran_digital_submit)
            Common::HashHelpers.deep_remove_blanks(a) # removes nil and blank values (but not false)
          end
        end
      end

      def organization_data
        membership =
          @power_of_attorney_holder_memberships.find(
            poa_request.power_of_attorney_holder_poa_code
          )

        {
          poaCode: membership.power_of_attorney_holder.poa_code,
          registrationNumber: membership.registration_number
        }
      end

      def veteran_data
        return nil if Flipper.enabled?(:form2122_non_veteran_digital_submit) && form_data['veteran'].blank?

        {}.tap do |v|
          v[:address] = address_data(form_data.dig('veteran', 'address'))
          v[:phone] = phone_data(form_data.dig('veteran', 'phone'))
          v[:email] = form_data.dig('veteran', 'email')
          if Flipper.enabled?(:form2122_non_veteran_digital_submit) ||
             form_data.dig('veteran', 'serviceNumber').present?
            v[:serviceNumber] = form_data.dig('veteran', 'serviceNumber')
          end
          if Flipper.enabled?(:form2122_non_veteran_digital_submit) ||
             form_data.dig('veteran', 'insuranceNumber').present?
            v[:insuranceNumber] = form_data.dig('veteran', 'insuranceNumber')
          end
        end
      end

      def claimant_data
        return nil if form_data['dependent'].blank?

        {
          claimantId: claimant_icn,
          address: address_data(form_data.dig('dependent', 'address')),
          relationship: form_data.dig('dependent', 'relationship'),
          # optional fields
          dateOfBirth: form_data.dig('dependent', 'dateOfBirth'),
          phone: phone_data(form_data.dig('dependent', 'phone')),
          email: form_data.dig('dependent', 'email')
        }
      end

      def phone_data(phone)
        return nil if Flipper.enabled?(:form2122_non_veteran_digital_submit) && phone.blank?

        phone_number = phone.to_s.gsub(/-| /, '')
        {}.tap do |p|
          p[:areaCode] = phone_number[0..2]
          p[:phoneNumber] = phone_number[3..9]
        end
      end

      def address_data(address)
        return nil if Flipper.enabled?(:form2122_non_veteran_digital_submit) && address.blank?

        {}.tap do |a|
          a[:addressLine1] = address['addressLine1']
          if Flipper.enabled?(:form2122_non_veteran_digital_submit) || address['addressLine2'].present?
            a[:addressLine2] = address['addressLine2']
          end
          a[:city] = address['city']
          a[:stateCode] = address['stateCode']
          a[:countryCode] = address['country']
          a[:zipCode] = address['zipCode'] if address['country'] == 'US'
          if Flipper.enabled?(:form2122_non_veteran_digital_submit) || address['zipCodeSuffix'].present?
            a[:zipCodeSuffix] = address['zipCodeSuffix']
          end
        end
      end
    end
  end
end
