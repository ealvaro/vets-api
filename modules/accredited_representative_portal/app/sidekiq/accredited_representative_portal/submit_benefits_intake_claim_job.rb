# frozen_string_literal: true

module AccreditedRepresentativePortal
  class SubmitBenefitsIntakeClaimJob < Lighthouse::SubmitBenefitsIntakeClaim
    ATTEMPT_METRIC_SUBMIT = 'ar.claims.form_upload.submit.attempt'
    SUCCESS_METRIC_SUBMIT = 'ar.claims.form_upload.submit.success'
    ERROR_METRIC_SUBMIT = 'ar.claims.form_upload.submit.error'

    def perform(saved_claim_id)
      super
      monitoring = ar_monitoring
      monitoring.track_count(SUCCESS_METRIC_SUBMIT)
    rescue
      monitoring = ar_monitoring
      monitoring.track_count(ERROR_METRIC_SUBMIT, tags: ['reason:unknown_error'])
      raise
    end

    ##
    # TODO: Remove this parent class override.
    #
    # This is a temporary workaround while there is configuration inconsistency
    # between two Benefits Intake API Ruby clients in `vets-api`'s staging
    # environment. The inconsistency between these Ruby clients matters because
    # we use both of them in different parts of claims' lifecycles:
    #
    # - `BenefitsIntakeService::Service`
    #   - Points to Lighthouse's staging environment
    #   - Used to submit claims initially
    # - `BenefitsIntake::Service`
    #   - Points to Lighthouse's sandbox environment
    #   - Used to check claims' statuses afterwards
    #
    def init(saved_claim_id)
      @claim = ::SavedClaim.find(saved_claim_id)
      monitoring = ar_monitoring
      monitoring.track_count(ATTEMPT_METRIC_SUBMIT)
      @lighthouse_service = lighthouse_service
    end

    def service
      if Flipper.enabled?(:accredited_representative_portal_lighthouse_api_key)
        ::AccreditedRepresentativePortal::BenefitsIntakeService.new
      else
        ::BenefitsIntakeService::Service.new.tap do |svc|
          svc.define_singleton_method(:config) do
            BenefitsIntake::Service.configuration
          end
        end
      end
    end

    def lighthouse_service
      service.tap do |service|
        upload = service.get_location_and_uuid
        service.instance_variable_set(:@uuid, upload[:uuid])
        service.instance_variable_set(:@location, upload[:location])
      end
    end

    ##
    # Overrides parent class.
    #
    def generate_metadata
      veteran = @claim.parsed_form['veteran']
      veteran_name = veteran['name']

      ::BenefitsIntake::Metadata.generate(
        veteran_name['first'],
        veteran_name['last'],
        veteran['ssn'],
        veteran['postalCode'],
        "#{@claim.class} va.gov",
        @claim.proper_form_id,
        @claim.class::BUSINESS_LINE
      )
    end

    def stamping_form_class
      @claim.class::STAMPING_FORM_CLASS
    end

    def current_time_string
      "#{Time.current.utc.strftime('%H:%M:%S  %Y-%m-%d %I:%M %p')} UTC"
    end

    def footer_stamp_text
      "Submitted via VA.gov at #{current_time_string}. Signed in and submitted with an identity-verified account."
    end

    ##
    # Overrides parent class.
    #
    def stamp_pdf(record)
      case record
      when ::PersistentAttachments::VAFormDocumentation
        pdf_path = record.to_pdf

        PDFUtilities::DatestampPdf.new(pdf_path).run(
          text: footer_stamp_text, x: 5, y: 5, text_only: true
        )
      when SavedClaim::BenefitsIntake
        record.to_pdf.tap do |stamped_template_path|
          ##
          # TODO: Reimplement PDF stamping with our own code. `SimpleFormsApi`'s
          # abstraction stamps the PDF, but it also fills out forms, which we may
          # not need.
          #
          SimpleFormsApi::PdfStamper.new(
            form: stamping_form_class&.new({}),
            form_number: @claim.proper_form_id,
            stamped_template_path:,
            current_loa: SignIn::Constants::Auth::LOA_THREE,
            timestamp: @claim.created_at
          ).stamp_pdf
        end
      else
        raise ArgumentError
      end
    end

    private

    def ar_monitoring
      form_id = @claim&.proper_form_id || 'unknown'
      org_code = @claim&.power_of_attorney_holder_poa_code
      org_code = 'N/A' if org_code.blank?

      AccreditedRepresentativePortal::Monitoring.new(
        AccreditedRepresentativePortal::Monitoring::NAME,
        default_tags: [
          "form_id:#{form_id}",
          "org:#{org_code}",
          ("bdd_status:#{bdd_status}" if @claim&.form_id&.include?('526EZ'))
        ].compact
      )
    end

    def bdd_status
      if @claim.parsed_form['benefitsDeliveryDischarge']
        @claim.separation_health_assessment.present? ? 'bdd_with_sha' : 'bdd_without_sha'
      else
        'non_bdd'
      end
    end
  end
end
