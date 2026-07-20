# frozen_string_literal: true

require 'bgs/service'
require 'dependents_benefits/claim_processor'
require 'dependents_benefits/generators/claim674_generator'
require 'dependents_benefits/generators/claim686c_generator'
require 'dependents_benefits/monitor'
require 'dependents_benefits/user_data'

require 'claims_evidence_api/uploader'
require 'digital_forms_api/service/submissions'
require 'pdf_utilities/pdf_stamper'

require 'bep/persons/service'

module DependentsBenefits
  module V0
    ###
    # The Dependents Benefits claim controller that handles form submissions
    #
    class ClaimsController < ClaimsBaseController
      before_action :load_user, only: %i[create show]
      before_action :check_flipper_flag

      wrap_parameters :dependents_application, format: [:json]

      service_tag 'dependent-change'

      # Returns a list of dependents for the current user
      def show
        dependents = create_dependent_service.get_dependents
        dependents[:diaries] = dependency_verification_service.read_diaries
        if Flipper.enabled?(:enable_date_last_verified_for_dependents)
          dependents[:bip_persons_data] = fetch_persons_api_data
        end
        render json: DependentsBenefits::DependentsSerializer.new(dependents)
      rescue => e
        monitor.track_show_error(nil, current_user, e)
        raise Common::Exceptions::BackendServiceException.new(nil, detail: e.message)
      end

      def create # rubocop:disable Metrics/MethodLength
        claim = create_parent_claim(dependent_params.to_json)

        # Populate the form_start_date from the IPF if available
        in_progress_form = fetch_in_progress_form
        claim.form_start_date = in_progress_form.created_at if in_progress_form

        unless claim.save
          monitor.track_create_validation_error(in_progress_form, claim, current_user)
          log_validation_error_to_metadata(in_progress_form, claim)
          raise Common::Exceptions::ValidationErrors, claim
        end

        claim_id = claim.id

        if !claim.submittable_686? && !claim.submittable_674?
          detail = 'Claim is not determinable to be a 686c or 674!'
          monitor.track_error_event(detail, action: 'create_claim', claim_id:)
          raise Common::Exceptions::BackendServiceException.new(nil, detail:)
        end

        claim.process_attachments!
        user_data = DependentsBenefits::UserData.new(current_user, claim.parsed_form)

        # Matching parent_claim_id and saved_claim_id indicates this is a parent claim
        SavedClaimGroup.new(claim_group_guid: claim.guid, parent_claim_id: claim_id, saved_claim_id: claim_id,
                            user_data: user_data.get_user_json).save!
        form_data = claim.parsed_form

        # FDF pilot
        # TODO move to separate job (future)
        forms_api_enabled = Flipper.enabled?(:dependents_digital_forms_api_submission_enabled, current_user)
        if forms_api_enabled && (claim.claim_form_type == '21-686c')
          begin
            claim_info = claim.get_claim_information(current_user)
            if claim_info[:proc_state] == 'MANUAL_VAGOV' && claim_info[:participant_id].present?
              claim.add_veteran_info(JSON.parse(user_data.get_user_json))

              submission = submit_via_forms_api(claim, claim_info[:claim_label], claim_info[:participant_id])
              upload_evidence_documents(claim, claim_info[:participant_id])

              monitor.track_create_success(in_progress_form, claim, current_user)
              DependentsBenefits::NotificationEmail.new(claim.id).send_submitted_notification

              # serialize and add FDF submission information
              response = SavedClaimSerializer.new(claim).serializable_hash
              response[:data][:digital_forms_api] = { submission: }

              clear_saved_form(claim.form_id)
              return render json: response
            end
          rescue => e
            context = {
              error: e.message,
              tags: ['status:error']
            }
            monitor.track_request(:error, e.message, 'dependents_controller.forms_api_submission', **context)
          end
        end

        # Create a 686c claim for dependent benefits
        DependentsBenefits::Generators::Claim686cGenerator.new(form_data, claim_id).generate if claim.submittable_686?

        if claim.submittable_674?
          # Create a 674 claim for student benefits
          form_data.dig('dependents_application', 'student_information')&.each do |student|
            DependentsBenefits::Generators::Claim674Generator.new(form_data, claim_id, student).generate
          end
        end

        monitor.track_create_success(in_progress_form, claim, current_user)

        # Enqueue all submission jobs for the created claim.
        DependentsBenefits::ClaimProcessor.enqueue_submissions(claim.id)

        clear_saved_form(in_progress_form.form_id) if in_progress_form

        render json: SavedClaimSerializer.new(claim)
      end

      private

      # submit claim to forms api - temp for FDF pilot
      # TODO move to job (future)
      def submit_via_forms_api(claim, claim_label, participant_id) # rubocop:disable Metrics/MethodLength
        digital_forms_api_submission_service ||= DigitalFormsApi::Service::Submissions.new

        payload = claim.fdf_submission_payload
        metadata = {
          sourceRequestId: claim.guid,
          formId: claim.claim_form_type,
          veteranId: participant_id,
          claimantId: participant_id,
          epCode: claim_label[/^\d+/],
          claimLabel: claim_label
        }

        response = digital_forms_api_submission_service.submit(payload, metadata)
        raise response.to_s unless response.success?

        submission = response.body['submission'].presence || {}
        context = {
          form_id: claim.form_id,
          saved_claim_id: claim.id,
          confirmation_number: claim.guid,
          submission_id: submission['submissionId'],
          claim_id: submission.dig('claim', 'claimId'),
          claim_label: submission.dig('claim', 'claimLabel'),
          tags: ['status:success']
        }
        monitor.track_request(:info, 'success', 'dependents_controller.forms_api_submission', **context)

        submission
      end

      # upload evidence documents - temp for FDF pilot
      # TODO eliminate and reuse the existing job (future)
      def upload_evidence_documents(claim, participant_id)
        form_id = claim.claim_form_type
        doctype = claim.document_type

        folder_identifier = "VETERAN:PARTICIPANT_ID:#{participant_id}"
        claims_evidence_uploader = ClaimsEvidenceApi::Uploader.new(folder_identifier)

        file_path = claim.to_pdf(form_id:, created_at: claim.created_at)
        claims_evidence_uploader.upload_evidence(claim.id, file_path:, form_id:, doctype:)

        stamp_set = [{ text: 'VA.GOV', x: 5, y: 5 }]
        claim.persistent_attachments.each do |pa|
          doctype = pa.document_type
          file_path = PDFUtilities::PDFStamper.new(stamp_set).run(pa.to_pdf, timestamp: pa.created_at)
          claims_evidence_uploader.upload_evidence(claim.id, pa.id, file_path:, form_id:, doctype:)
        end
      rescue => e
        metric = "#{DependentsBenefits::Monitor::CLAIM_STATS_KEY}.submit_pdf.failure"
        monitor.track_request(:error, 'Evidence submission during Forms API processing failed',
                              metric, error: e.message)
      end

      # Limits the allowed parameters for dependents benefits claim submissions
      def dependent_params
        params.permit(
          :add_spouse,
          :veteran_was_married_before,
          :add_child,
          :report674,
          :report_divorce,
          :spouse_was_married_before,
          :report_stepchild_not_in_household,
          :report_death,
          :report_marriage_of_child_under18,
          :report_child18_or_older_is_not_attending_school,
          :statement_of_truth_signature,
          :statement_of_truth_certified,
          'view:selectable686_options': {},
          dependents_application: {},
          supporting_documents: []
        )
      end

      # Creates a new claim instance with the provided form parameters.
      #
      # @param form_params [String] The JSON string for the claim form.
      # @return [Claim] A new instance of the claim class initialized with the given attributes.
      #   If the current user has an associated user account, it is included in the claim attributes.
      def create_parent_claim(form_params)
        claim_attributes = { form: form_params }
        claim_attributes[:user_account] = @current_user.user_account if @current_user&.user_account

        DependentsBenefits::PrimaryDependencyClaim.new(**claim_attributes)
      end

      # Raises an exception if the dependents verification flipper flag isn't enabled.
      def check_flipper_flag
        raise Common::Exceptions::Forbidden unless Flipper.enabled?(:dependents_module_enabled, current_user)
      end

      # Creates the BGS dependent service for the current user
      def create_dependent_service
        @dependent_service ||= BGS::DependentService.new(current_user)
      end

      # Creates the BGS dependency verification service for the current user
      def dependency_verification_service
        @dependency_verification_service ||= BGS::DependencyVerificationService.new(current_user)
      end

      # Finds the relevant InProgressForm
      def fetch_in_progress_form
        # While we transition from non-modularized 686 to modularized 686
        # there will be a little overlap in what `form_id` is being used
        # for InProgressForms. So rather than just checking for claim.form_id
        # we need to check for the alternate form_id as well. Fortunately, the
        # two form versions use the exact same schema and front end, so their
        # InProgressFrom representations are interchangeable
        return nil unless current_user

        InProgressForm.form_for_user(DependentsBenefits::FORM_ID_V2, current_user) ||
          InProgressForm.form_for_user(DependentsBenefits::FORM_ID, current_user)
      end

      # Calls the Persons API to fetch additional information for a users dependents,
      # in particular we are interested in the last verified date
      def fetch_persons_api_data
        monitor.track_info_event('Fetching last verified dates',
                                 action: 'fetch_dlv.start')

        service = BEP::Persons::Service.new(current_user)
        response = service.get_relationships(current_user.participant_id)

        if response.success?
          data = response.body['find_relationships_response']
          num_dlv = data.count { |e| e['last_verfd_dt'].present? }
          monitor.track_info_event('Successfully fetched last verified dates', action: 'fetch_dlv.success',
                                                                               non_blank_dlvs: num_dlv)
          data
        else
          monitor.track_error_event('Unsuccessful response when fetching last verified dates',
                                    action: 'fetch_dlv.failed_response', error: response.body)
          []
        end
      rescue => e
        monitor.track_error_event('Failed to fetch last verified dates',
                                  action: 'fetch_dlv.error',
                                  error: e)
        []
      end

      ##
      # Include validation error on in_progress_form metadata.
      # `noop` if in_progress_form is `blank?`
      #
      # @param in_progress_form [InProgressForm]
      # @param claim [DependentsBenefits::PrimaryDependencyClaim]
      #
      # @return [void]
      def log_validation_error_to_metadata(in_progress_form, claim)
        return if in_progress_form.blank?

        metadata = in_progress_form.metadata || {}
        metadata['submission'] ||= {}
        metadata['submission']['error_message'] = claim&.errors&.errors&.to_s
        in_progress_form.update(metadata:)
      end

      # Creates a new monitor instance for tracking events
      def monitor
        @monitor ||= DependentsBenefits::Monitor.new(nil, current_user)
      end
    end
  end
end
