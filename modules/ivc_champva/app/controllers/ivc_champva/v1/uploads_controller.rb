# frozen_string_literal: true

require 'datadog'
require 'ves_api/client'
require 'common/pdf_helpers'

# rubocop:disable Metrics/ClassLength
# Note: Disabling this rule is temporary, refactoring of this class is planned
module IvcChampva
  module V1
    class UploadsController < ApplicationController
      skip_after_action :set_csrf_header

      include ActionView::Helpers::NumberHelper

      FORM_NUMBER_MAP = {
        '10-10D' => 'vha_10_10d',
        '10-10D-EXTENDED' => 'vha_10_10d',
        '10-10D-SUPPLEMENTAL' => 'vha_10_10d',
        '10-7959F-1' => 'vha_10_7959f_1',
        '10-7959F-2' => 'vha_10_7959f_2',
        '10-7959C' => 'vha_10_7959c',
        '10-7959A' => 'vha_10_7959a'
      }.freeze

      RETRY_ERROR_CONDITIONS = [
        'failed to generate',
        'no such file',
        'an error occurred while verifying stamp:',
        'unable to find file'
      ].freeze
      # submission_type values that mean supporting-docs-only (not a full new application).
      DOCS_ONLY_RESUBMISSION_SUBMISSION_TYPES = %w[existing enrollment].freeze

      # form_number values allowed to use the docs-only resubmission path.
      DOCS_ONLY_RESUBMISSION_FORM_NUMBERS = %w[10-10D-EXTENDED 10-10D-SUPPLEMENTAL].freeze

      def submit(form_data = nil)
        Datadog::Tracing.trace('IVC Champva Forms - Submit Form') do
          form_id = get_form_id
          Datadog::Tracing.active_trace&.set_tag('form_id', form_id)
          # This allows us to call submit internally (for 10-10d/10-7959c merged
          # form) without messing with the shared param object across functions
          parsed_form_data = form_data || JSON.parse(params.to_json)

          validate_mpi_profiles(parsed_form_data, form_id)

          response = handle_file_uploads_wrapper(form_id, parsed_form_data)

          if @current_user && response[:status] == 200
            InProgressForm.form_for_user(params[:form_number], @current_user)&.destroy!
          end

          render json: response[:json], status: response[:status]
        end
      rescue ArgumentError => e
        Rails.logger.error "Validation error in IVC ChampVA submission: #{e.message}"
        render json: { error_message: e.message }, status: :unprocessable_entity
      rescue => e
        Rails.logger.error "Error: #{e.message}"
        Rails.logger.error e.backtrace.join("\n")
        render json: { error_message: "Error: #{e.message}" }, status: :internal_server_error
      end

      def validate_mpi_profiles(parsed_form_data, form_id)
        if Flipper.enabled?(:champva_mpi_validation, @current_user) && form_id == 'vha_10_10d'
          Datadog::Tracing.trace('IVC Champva Forms - Validate MPI Profiles') do
            # Query MPI and log validation results for veteran and beneficiaries on 10-10D submissions
            IvcChampva::MPIService.new.validate_profiles(parsed_form_data)
          rescue => e
            Rails.logger.error "Error validating MPI profiles: #{e.message}"
          end
        end
      end

      # This method handles generating OHI forms for all appropriate applicants
      # when a user submits a 10-10d/10-7959c merged form.
      def submit_champva_app_merged
        Datadog::Tracing.trace('IVC Champva Forms - Submit Merged 10-10d + OHI') do
          parsed_form_data = JSON.parse(params.to_json)

          flow = docs_only_resubmission_flow(parsed_form_data)

          if flow == :cst
            submit_merged_docs_only_cst(parsed_form_data)
          elsif flow == :form_submission
            submit_merged_docs_only_form_submission(parsed_form_data)
          else
            process_standard_merged_champva_submission(parsed_form_data)
          end
        end
      rescue ArgumentError => e
        Rails.logger.error "Validation error in IVC ChampVA merged submission: #{e.message}"
        render json: { error_message: e.message }, status: :unprocessable_entity
      rescue => e
        log_error_and_respond("Error submitting merged form: #{e.message}", e)
      end

      def submit_merged_docs_only_cst(parsed_form_data)
        validate_docs_only_resubmission!(parsed_form_data) if parsed_form_data['claim_id'].present?
        hydrate_docs_only_resubmission_data(parsed_form_data) if parsed_form_data['claim_id'].present?
        IvcChampva::MetadataValidator.validate_docs_only_resubmission_cst(parsed_form_data)

        response = process_docs_only_resubmission(parsed_form_data)
        render json: response.fetch(:json), status: response.fetch(:status)
      end

      def submit_merged_docs_only_form_submission(parsed_form_data)
        IvcChampva::MetadataValidator.validate_docs_only_resubmission_cst(parsed_form_data)

        response = process_docs_only_resubmission(parsed_form_data)
        render json: response.fetch(:json), status: response.fetch(:status)
      end

      def process_standard_merged_champva_submission(parsed_form_data)
        Datadog::Tracing.trace('IVC Champva Forms - Generate OHI Forms for Each Applicant') do
          form_id = get_form_id
          apps = applicants_with_ohi(parsed_form_data['applicants'])

          apps.each do |app|
            # Generate OHI forms for each applicant. Creates one form per 2 policies
            # to handle overflow when applicant has more than 2 health insurance policies.
            ohi_forms = generate_ohi_form(app, parsed_form_data)
            ohi_forms.each do |f|
              ohi_path = fill_ohi_and_return_path(f)
              ohi_supporting_doc = create_custom_attachment(f, ohi_path, 'VA form 10-7959c')
              add_supporting_doc(parsed_form_data, ohi_supporting_doc)
              f.track_delegate_form(form_id) if f.respond_to?(:track_delegate_form)
            end
          end
        end

        submit(parsed_form_data)
      end

      def submit_docs_only_resubmission
        parsed_form_data = parse_docs_only_payload
        ensure_docs_only_resubmission_enabled(parsed_form_data)
        validate_docs_only_resubmission!(parsed_form_data)
        hydrate_docs_only_resubmission_data(parsed_form_data)
        IvcChampva::MetadataValidator.validate_docs_only_resubmission(parsed_form_data)

        response = process_docs_only_resubmission(parsed_form_data)
        render json: response.fetch(:json), status: response.fetch(:status)
      rescue ArgumentError => e
        handle_docs_only_resubmission_argument_error(e)
      rescue => e
        handle_docs_only_resubmission_unexpected_error(e)
      end

      ##
      # Handles PEGA/S3 file uploads and VES submission
      #
      # @param [String] form_id The ID of the current form, e.g., 'vha_10_10d' (see FORM_NUMBER_MAP)
      # @param [Hash] parsed_form_data complete form submission data object
      #
      # @return [Hash] response from build_json
      def handle_file_uploads_wrapper(form_id, parsed_form_data)
        file_paths, metadata = get_file_paths_and_metadata(parsed_form_data)

        if should_process_ves?(form_id) && !docs_only_resubmission_flow_enabled?(parsed_form_data)
          handle_ves_submission(form_id, file_paths, metadata, parsed_form_data)
        else
          statuses, error_messages = handle_file_uploads(form_id, file_paths, metadata, parsed_form_data)
          build_json(statuses, error_messages)
        end
      end

      # Determines if this form should be processed through VES flow
      def should_process_ves?(form_id)
        return true if form_id == 'vha_10_10d'
        return true if Flipper.enabled?(:champva_send_7959c_to_ves, @current_user) && form_id == 'vha_10_7959c'

        false
      end

      # Handles VES submission flow for supported forms (10-10D, 10-7959C standalone)
      def handle_ves_submission(form_id, file_paths, metadata, parsed_form_data)
        # Prepare VES request using form_uuid as application_uuid for consistency
        ves_request = prepare_ves_request(parsed_form_data, form_uuid: metadata['uuid'])

        statuses, error_messages = handle_file_uploads(form_id, file_paths, metadata, parsed_form_data)
        response = build_json(statuses, error_messages)

        submit_to_ves(ves_request, metadata) if response[:status] == 200

        response
      ensure
        ves_json_files = file_paths&.select { |p| IvcChampva::FileNaming.ves_json?(p) } || []
        ves_json_files.each { |f| FileUtils.rm_f(f) }
      end

      # Routes VES submission based on request type.
      # By this point, flipper checks are complete - just route based on request structure.
      #
      # @param [IvcChampva::VesRequest, Array<IvcChampva::VesOhiRequest>] ves_request
      # @param [Hash] metadata
      def submit_to_ves(ves_request, metadata)
        Datadog::Tracing.trace('IVC Champva Forms - Submit to VES') do
          return if ves_request.nil?

          ves_client = IvcChampva::VesApi::Client.new

          if ves_request.is_a?(Array)
            # Standalone OHI submissions
            submit_ves_requests(ves_client, ves_request, metadata)
          elsif ves_request.subforms?
            # 10-10D-EXTENDED: submit parent, then subforms on success
            response = submit_ves_form(ves_client, ves_request, metadata)
            if response&.status == 200
              subform_requests = ves_request.subforms.map { |sf| sf[:request] }
              submit_ves_requests(ves_client, subform_requests, metadata)
            end
          else
            # Standard 10-10D
            submit_ves_form(ves_client, ves_request, metadata)
          end
        end
      end

      # Submits multiple VES requests.
      #
      # @param [IvcChampva::VesApi::Client] ves_client
      # @param [Array] requests - Array of request objects (each must respond to #form_type)
      # @param [Hash] metadata
      def submit_ves_requests(ves_client, requests, metadata)
        return if requests.blank?

        requests.each do |request|
          submit_ves_form(ves_client, request, metadata)
        rescue => e
          Rails.logger.error "Error submitting VES request: #{e.message}"
        end
      end

      ##
      # Determines if VES JSON should be generated as a supporting document
      #
      # @param [String] form_id The ID of the current form
      # @return [Boolean] true if VES JSON should be generated
      def should_generate_ves_json?(form_id)
        # Get the legacy form ID to handle versioned forms (e.g., vha_10_10d_2027 -> vha_10_10d)
        legacy_form_id = IvcChampva::FormVersionManager.get_legacy_form_id(form_id)
        Flipper.enabled?(:champva_send_ves_to_pega, @current_user) && legacy_form_id == 'vha_10_10d'
      end

      ##
      # Generates VES JSON file and returns the file path
      #
      # @param [Object] form The form instance with proper UUID and form_id
      # @param [Hash] parsed_form_data complete form submission data object
      # @return [String] The path to the generated VES JSON file
      def generate_ves_json_file(form, parsed_form_data)
        Datadog::Tracing.trace('IVC Champva Forms - Generate VES JSON File') do
          # Generate VES data using form.uuid as application_uuid for consistency
          ves_data = IvcChampva::VesDataFormatter.format_for_request(parsed_form_data, form_uuid: form.uuid)

          # Create temporary JSON file using form.uuid (absolute path like PDF files)
          ves_file_path = Rails.root.join("tmp/#{form.uuid}_#{form.form_id}_ves.json").to_s
          File.write(ves_file_path, ves_data.to_json)

          Rails.logger.info "VES JSON file generated for form #{form.form_id}: #{ves_file_path}"
          ves_file_path
        end
      rescue => e
        # Don't raise - we don't want VES JSON generation failure to break the entire submission
        Rails.logger.error "Error generating VES JSON file for form #{form.form_id}: #{e.message}"
        nil
      end

      ##
      # Generates VES JSON files for all forms in a submission under the new OHI flag.
      # Branches by form_number, mirroring prepare_ves_request. Produces one file per form.
      #
      # @param [Object] form The form instance with proper UUID and form_id
      # @param [Hash] parsed_form_data complete form submission data object
      # @return [Array<Hash>] Array of { path:, attachment_id: } hashes
      def generate_ves_json_files(form, parsed_form_data)
        Datadog::Tracing.trace('IVC Champva Forms - Generate VES JSON Files') do
          case parsed_form_data['form_number']
          when '10-10D'
            write_1010d_ves_json(form, parsed_form_data)
          when '10-10D-EXTENDED'
            write_1010d_ves_json(form, parsed_form_data)
              .concat(write_ohi_ves_json_files(form, parsed_form_data))
          when '10-7959C'
            write_ohi_ves_json_files(form, parsed_form_data)
          else
            []
          end
        end
      rescue => e
        Rails.logger.error "Error generating VES JSON file(s) for form #{form.form_id}: #{e.message}"
        []
      end

      # Prepares data for VES based on form type and feature flags.
      #
      # When champva_send_7959c_to_ves is ENABLED:
      # - 10-10D: format_for_request (standalone)
      # - 10-10D-EXTENDED: format_for_extended_request (with OHI subforms)
      # - 10-7959C: format_for_ohi_request (standalone OHI)
      #
      # When champva_send_7959c_to_ves is DISABLED (legacy flow):
      # - All 10-10D variants: format_for_request (no subforms)
      # - 10-7959C: should not reach here (blocked by should_process_ves?)
      #
      # @param [Hash] parsed_form_data complete form submission data object
      # @param [String] form_uuid the UUID to use as application_uuid (aligns VES with form records)
      # @return [IvcChampva::VesRequest, Array<IvcChampva::VesOhiRequest>, nil] the formatted request data
      def prepare_ves_request(parsed_form_data, form_uuid:)
        Datadog::Tracing.trace('IVC Champva Forms - Prepare VES Request') do
          form_number = parsed_form_data['form_number']

          ves_request = if Flipper.enabled?(:champva_send_7959c_to_ves, @current_user)
                          case form_number
                          when '10-10D'
                            IvcChampva::VesDataFormatter.format_for_request(parsed_form_data, form_uuid:)
                          when '10-10D-EXTENDED'
                            IvcChampva::VesDataFormatter.format_for_extended_request(parsed_form_data, form_uuid:)
                          when '10-7959C'
                            IvcChampva::VesDataFormatter.format_for_ohi_request(parsed_form_data, form_uuid:)
                          else
                            # This should not happen - should_process_ves? should filter unsupported forms
                            Rails.logger.warn("VES: Unexpected form_number '#{form_number}' in prepare_ves_request")
                            nil
                          end
                        else
                          # Legacy flow: all 10-10D variants use format_for_request (no subforms)
                          IvcChampva::VesDataFormatter.format_for_request(parsed_form_data, form_uuid:)
                        end

          raise 'Failed to format data for VES submission' if ves_request.nil?

          ves_request
        end
      end

      ##
      # Submits a VES form request with retry logic.
      #
      # @param [IvcChampva::VesApi::Client] ves_client the VES API client
      # @param [Object] request the VES request object (VesRequest or VesOhiRequest)
      # @param [Hash] metadata the metadata for the form
      # @return [Faraday::Response, nil] the VES API response or nil on failure
      def submit_ves_form(ves_client, request, metadata)
        form_type = request.form_type
        on_failure = ->(e, attempt) { log_ves_retry_failure(form_type, attempt, e) }
        response = nil

        begin
          IvcChampva::Retry.do(1, on_failure:) do
            request.transaction_uuid = SecureRandom.uuid
            response = send_to_ves_by_form_type(ves_client, request)
          end
        rescue => e
          Rails.logger.error("VES Submission: Error for #{form_type}", e)
        ensure
          ves_request_data = ves_request_data_for_storage(form_type, request)
          update_ves_records(metadata['uuid'], request.application_uuid, response, ves_request_data,
                             request.transaction_uuid)
        end

        response
      end

      def log_ves_retry_failure(form_type, attempt, error)
        Rails.logger.error("VES Submission: Retry attempt #{attempt} failed for #{form_type}", error)
      end

      # Determines what VES request data to store based on form type.
      # Only store for 10-10D; OHI forms can be reconstructed from request_json.
      def ves_request_data_for_storage(form_type, request)
        form_type == 'vha_10_10d' ? request.to_json : nil
      end

      ##
      # Routes the VES submission to the appropriate client method based on form type.
      #
      # @param [IvcChampva::VesApi::Client] ves_client the VES API client
      # @param [Object] request the VES request object (must respond to #form_type)
      # @return [Faraday::Response] the VES API response
      def send_to_ves_by_form_type(ves_client, request)
        if request.form_1010d? || request.form_1010dx?
          ves_client.submit_1010d(request.transaction_uuid, request)
        elsif request.form_7959c?
          ves_client.submit_7959c(request.transaction_uuid, request)
        else
          raise ArgumentError, "Unknown VES form type: #{request.form_type}"
        end
      end

      def update_ves_records(form_uuid, application_uuid, ves_response, ves_request_data, transaction_uuid = nil)
        # this should be unique
        persisted_forms = IvcChampvaForm.where(form_uuid:)

        # ves_response in the db is freeform text and hard to parse
        # so only put the response body in the db if the response is not 200
        ves_status = if ves_response.nil?
                       'internal_server_error'
                     else
                       ves_response.status == 200 ? 'ok' : ves_response.body
                     end

        persisted_forms.each do |form|
          attrs = {
            application_uuid:,
            ves_status:,
            ves_request_data:
          }
          # Only set transaction_uuid when we have one and the row doesn't already
          # have one — prevents subform submissions from overwriting the parent
          # 10-10D UUID that is needed for later VES ICN lookups.
          attrs[:transaction_uuid] = transaction_uuid if transaction_uuid.present? && form.transaction_uuid.blank?
          form.update(attrs)
        end
      end

      # Modified from claim_documents_controller.rb:
      def unlock_file(file, file_password)
        Datadog::Tracing.trace('IVC Champva Forms - Unlock File') do
          return file unless File.extname(file) == '.pdf' && file_password

          tmpf = Tempfile.new(['decrypted_form_attachment', '.pdf'])

          tmpf = if Flipper.enabled?(:champva_use_hexapdf_to_unlock_pdfs, @current_user)
                   unlock_with_hexapdf(file, file_password, tmpf)
                 else
                   unlock_with_pdftk(file, file_password, tmpf)
                 end

          file.tempfile.unlink
          file.tempfile = tmpf
        end
      end

      ## Uses pdftk to unlock the provided PDF file with the given password
      # @param [ActionDispatch::Http::UploadedFile] source_file The uploaded PDF file to unlock
      # @param [String] file_password The password to unlock the PDF
      # @param [Tempfile] destination_file A tempfile where the unlocked PDF will be saved
      def unlock_with_pdftk(source_file, file_password, destination_file)
        pdftk = PdfForms.new(Settings.binaries.pdftk)

        has_pdf_err = false
        begin
          pdftk.call_pdftk(source_file.tempfile.path, 'input_pw', file_password, 'output', destination_file.path)
        rescue PdfForms::PdftkError => e
          file_regex = %r{/(?:\w+/)*[\w-]+\.pdf\b}
          password_regex = /(input_pw).*?(output)/
          sanitized_message = e.message.gsub(file_regex, '[FILTERED FILENAME]').gsub(password_regex, '\1 [FILTERED] \2')
          Rails.logger.warn(sanitized_message)
          has_pdf_err = true
        end

        # This helps prevent leaking exception context to DataDog when we raise this error
        if has_pdf_err
          raise Common::Exceptions::UnprocessableEntity.new(
            detail: IvcChampva::Constants::INCORRECT_PASSWORD_DETAIL,
            source: 'IvcChampva::V1::UploadsController'
          )
        end

        destination_file
      end

      ## Uses hexapdf to unlock the provided PDF file with the given password
      # @param [ActionDispatch::Http::UploadedFile] source_file The uploaded PDF file to unlock
      # @param [String] file_password The password to unlock the PDF
      # @param [Tempfile] destination_file A tempfile where the unlocked PDF will be saved
      def unlock_with_hexapdf(source_file, file_password, destination_file)
        has_pdf_err = false
        begin
          ::Common::PdfHelpers.unlock_pdf(source_file.tempfile.path, file_password, destination_file.path)
        rescue Common::Exceptions::UnprocessableEntity => e
          file_regex = %r{/(?:\w+/)*[\w-]+\.pdf\b}
          password_regex = /(input_pw).*?(output)/
          sanitized_message = e.message.gsub(file_regex, '[FILTERED FILENAME]').gsub(password_regex, '\1 [FILTERED] \2')
          Rails.logger.warn(sanitized_message)
          has_pdf_err = true
        end

        # This helps prevent leaking exception context to DataDog when we raise this error
        if has_pdf_err
          raise Common::Exceptions::UnprocessableEntity.new(
            detail: IvcChampva::Constants::INCORRECT_PASSWORD_DETAIL,
            source: 'IvcChampva::V1::UploadsController'
          )
        end

        destination_file
      end

      def submit_supporting_documents # rubocop:disable Metrics/MethodLength
        Datadog::Tracing.trace('IVC Champva Forms - Submit Supporting Document') do
          allowed_form_ids = %w[10-10D 10-7959C 10-7959F-2 10-7959A 10-10D-EXTENDED
                                10-10D-SUPPLEMENTAL 10-10D-SUPPLEMENTAL-EXISTING 10-10D-SUPPLEMENTAL-ENROLLMENT]
          form_id = submit_supporting_documents_params[:form_id]
          file = submit_supporting_documents_params[:file]
          password = submit_supporting_documents_params[:password]
          attachment_id = submit_supporting_documents_params[:attachment_id]

          if allowed_form_ids.include?(form_id)
            attachment = PersistentAttachments::MilitaryRecords.new(form_id:)
            attachment.heif_enabled = Flipper.enabled?(:champva_heif_attachments_enabled, @current_user)

            Rails.logger.info "submit_supporting_documents called for form #{form_id}"

            unlocked = unlock_file(file, password)
            attachment.file = password ? unlocked : file

            # pre-validation logging to help debug issues
            Rails.logger.info "submit_supporting_documents attachment.file class: #{attachment.file.class}"
            Rails.logger.info "submit_supporting_documents attachment.file present: #{attachment.file.present?}"
            Rails.logger.info(
              "submit_supporting_documents attachment.file size: #{number_to_human_size(attachment.file&.size)}"
            )

            Datadog::Tracing.trace('IVC Champva Forms - Validate Attachment') do
              unless attachment.valid?
                error_msgs = attachment.errors.full_messages.join(', ')
                Rails.logger.error "submit_supporting_documents attachment is invalid: #{error_msgs}"
                raise Common::Exceptions::ValidationErrors, attachment
              end
            end

            # Convert to PDF before save to reduce final submission latency
            if Flipper.enabled?(:champva_convert_to_pdf_on_upload, @current_user)
              attachment.file = convert_to_pdf(attachment.file)
            end

            Datadog::Tracing.trace('IVC Champva Forms - Save Attachment') do
              attachment.save
            end

            persist_claim_evidence_submission(attachment)

            launch_background_job(attachment, form_id.to_s, attachment_id)

            if Flipper.enabled?(:champva_claims_llm_validation, @current_user)
              # Prepare the base response
              response_data = PersistentAttachmentSerializer.new(attachment).serializable_hash

              # Add LLM analysis if enabled
              llm_result = call_llm_service(attachment, form_id, attachment_id)
              response_data[:llm_response] = llm_result if llm_result.present?

              render json: response_data
            else
              render json: PersistentAttachmentSerializer.new(attachment)
            end
          else
            raise Common::Exceptions::UnprocessableEntity.new(
              detail: "Unsupported form_id: #{form_id}",
              source: 'IvcChampva::V1::UploadsController'
            )
          end
        end
      end

      ##
      # Launches background jobs for OCR and LLM processing if enabled
      # @param [PersistentAttachments::MilitaryRecords] attachment Persistent attachment object for the uploaded file
      # @param [String] form_id The ID of the current form, e.g., 'vha_10_10d' (see FORM_NUMBER_MAP)
      def launch_background_job(attachment, form_id, attachment_id)
        Datadog::Tracing.trace('IVC Champva Forms - Launch OCR/LLM Job Asynchronously') do
          launch_ocr_job(form_id, attachment, attachment_id)
          launch_llm_job(form_id, attachment, attachment_id)
        end
      rescue Errno::ENOENT
        # Do not log the error details because they may contain PII
        Rails.logger.error 'Unhandled ENOENT error while launching background job(s)'
      rescue => e
        Rails.logger.error "Unhandled error while launching background job(s): #{e.message}"
      end

      def launch_ocr_job(form_id, attachment, attachment_id)
        if Flipper.enabled?(:champva_enable_ocr_on_submit, @current_user) && form_id == '10-7959A'
          begin
            # queue Tesseract OCR job for tmpfile
            IvcChampva::TesseractOcrLoggerJob.perform_async(form_id, attachment.guid, attachment.id, attachment_id,
                                                            @current_user)
            Rails.logger.info(
              "Tesseract OCR job queued for form_id: #{form_id}, attachment_id: #{attachment.guid}"
            )
          rescue => e
            Rails.logger.error "Error launching OCR job: #{e.message}"
          end
        end
      end

      def launch_llm_job(form_id, attachment, attachment_id)
        if Flipper.enabled?(:champva_enable_llm_on_submit, @current_user) && form_id == '10-7959A'
          begin
            # queue LLM job for attachment record
            IvcChampva::LlmLoggerJob.perform_async(form_id, attachment.guid, attachment.id, attachment_id,
                                                   @current_user)
            Rails.logger.info(
              "LLM job queued for form_id: #{form_id}, attachment_id: #{attachment.guid}"
            )
          rescue => e
            Rails.logger.error "Error launching LLM job: #{e.message}"
          end
        end
      end

      ##
      # Calls the LLM service synchronously for immediate response
      # @param [PersistentAttachments::MilitaryRecords] attachment The attachment object containing the file
      # @param [String] form_id The mapped form ID (e.g., '10-7959A')
      # @param [String] attachment_id The document type/attachment ID
      # @return [Hash, nil] LLM analysis result or nil if conditions not met
      def call_llm_service(attachment, form_id, attachment_id)
        Datadog::Tracing.trace('IVC Champva Forms - Call OCR/LLM Service Synchronously') do
          return nil unless Flipper.enabled?(:champva_claims_llm_validation, @current_user)
          return nil unless form_id == '10-7959A'

          begin
            # create a temp file from the persistent attachment object
            tmpfile = tempfile_from_attachment(attachment, form_id)
            pdf_path = Common::ConvertToPdf.new(tmpfile).run

            # Convert form_id to mapped format for LLM service
            mapped_form_id = FORM_NUMBER_MAP[form_id]

            # Call LLM service synchronously
            llm_service = IvcChampva::LlmService.new
            llm_service.process_document(
              form_id: mapped_form_id,
              file_path: pdf_path,
              uuid: attachment.guid,
              attachment_id:
            )
          rescue => e
            Rails.logger.error "Error calling LLM service: #{e.message}"
            nil
          end
        end
      end

      ## Saves the attached file as a temporary file
      # @param [PersistentAttachments::MilitaryRecords] attachment The attachment object containing the file
      # @param [String] form_id The ID of the current form, e.g., 'vha_10_10d' (see FORM_NUMBER_MAP)
      def tempfile_from_attachment(attachment, form_id)
        Datadog::Tracing.trace('IVC Champva Forms - Save Tempfile from Attachment') do
          original_filename = if attachment.file.respond_to?(:original_filename)
                                attachment.file.original_filename
                              else
                                File.basename(attachment.file.path)
                              end
          # base = File.basename(original_filename, File.extname(original_filename))
          ext = File.extname(original_filename)
          tmpfile = Tempfile.new(["#{form_id}_attachment_", ext]) # a timestamp and unique ID are added automatically
          tmpfile.binmode
          tmpfile.write(attachment.file.read)
          tmpfile.flush
          tmpfile.rewind

          content_type = if attachment.file.respond_to?(:content_type)
                           attachment.file.content_type
                         else
                           content_type_from_extension(ext)
                         end

          # Define content_type method on the tmpfile singleton
          tmpfile.define_singleton_method(:content_type) { content_type }

          tmpfile
        end
      end

      private

      ##
      # Generates a 10-10D VES request JSON file.
      #
      # @param [Object] form The form instance
      # @param [Hash] parsed_form_data complete form submission data
      # @return [Array<Hash>] Array of { path:, attachment_id: } hashes (empty on failure)
      def write_1010d_ves_json(form, parsed_form_data)
        ves_data = IvcChampva::VesDataFormatter.format_for_request(parsed_form_data, form_uuid: form.uuid)
        path = Rails.root.join("tmp/#{form.uuid}_#{form.form_id}_ves.json").to_s
        File.write(path, ves_data.to_json)
        Rails.logger.info "VES JSON file generated for form #{form.form_id}: #{path}"
        [{ path:, attachment_id: 'VES JSON' }]
      rescue => e
        Rails.logger.error "Error writing 1010d VES JSON: #{e.message}"
        []
      end

      ##
      # Generates one OHI VES JSON file per applicant with OHI data.
      #
      # @param [Object] form The form instance
      # @param [Hash] parsed_form_data complete form submission data
      # @return [Array<Hash>] Array of { path:, attachment_id: } hashes
      def write_ohi_ves_json_files(form, parsed_form_data)
        ohi_requests = IvcChampva::VesDataFormatter.format_for_ohi_request(parsed_form_data, form_uuid: form.uuid)
        return [] if ohi_requests.blank?

        ohi_requests.each_with_index.filter_map do |ohi_request, index|
          ohi_json = JSON.parse(ohi_request.to_json)
          path = Rails.root.join("tmp/#{form.uuid}_#{form.form_id}_ohi_ves_#{index}.json").to_s
          File.write(path, ohi_json.to_json)
          Rails.logger.info "OHI VES JSON file #{index} generated for form #{form.form_id}: #{path}"
          { path:, attachment_id: 'VES OHI JSON' }
        rescue => e
          Rails.logger.error "Error writing OHI VES JSON #{index}: #{e.message}"
          nil
        end
      end

      ##
      # Builds a mapping of file names to per-file metadata overrides.
      # FileUploader merges these overrides into each file's S3 metadata during upload.
      #
      # @param [Array<String>] file_paths all file paths including PDFs and VES JSONs
      # @param [Array<String>] attachment_ids positionally correlated with file_paths
      # @param [Array<Hash>] ves_json_results results from generate_ves_json_files
      # @param [String] legacy_form_id the legacy form ID (e.g., 'vha_10_10d')
      # @return [Hash] mapping of file names to metadata override hashes
      def build_additional_file_metadata(file_paths, attachment_ids, ves_json_results, legacy_form_id)
        additional = {}
        ves_json = ves_json_results.find { |r| r[:attachment_id] == 'VES JSON' }
        ohi_jsons = ves_json_results.select { |r| r[:attachment_id] == 'VES OHI JSON' }

        map_form_pdfs_to_ves_json(additional, file_paths, attachment_ids, ves_json, legacy_form_id) if ves_json
        map_ohi_pdfs_to_ves_json(additional, file_paths, attachment_ids, ohi_jsons)

        additional
      end

      def append_ves_json_files(form, parsed_form_data, collections)
        file_paths, attachment_ids, metadata, legacy_form_id = collections

        if Flipper.enabled?(:champva_send_ohi_ves_to_pega, @current_user)
          ves_json_results = generate_ves_json_files(form, parsed_form_data)
          ves_json_results.each do |result|
            file_paths << result[:path]
            attachment_ids << result[:attachment_id]
          end
          afm = build_additional_file_metadata(file_paths, attachment_ids, ves_json_results, legacy_form_id)
          metadata['additional_file_metadata'] = afm if afm.any?
        elsif should_generate_ves_json?(form.form_id)
          ves_json_path = generate_ves_json_file(form, parsed_form_data)
          if ves_json_path
            file_paths << ves_json_path
            attachment_ids << 'VES JSON'
          end
        end
      end

      def map_form_pdfs_to_ves_json(additional, file_paths, attachment_ids, ves_json, legacy_form_id)
        ves_basename = File.basename(ves_json[:path])
        file_paths.each_with_index do |fp, i|
          next if IvcChampva::FileNaming.ves_json?(fp)
          next unless attachment_ids[i] == legacy_form_id

          clean_name = File.basename(fp).gsub('-tmp', '')
          additional[clean_name] = (additional[clean_name] || {}).merge('meta-jsonfile' => ves_basename)
        end
      end

      def map_ohi_pdfs_to_ves_json(additional, file_paths, attachment_ids, ohi_jsons)
        ohi_pdf_paths = file_paths.each_with_index.select do |_fp, i|
          attachment_ids[i].in?(['VA form 10-7959c', 'vha_10_7959c'])
        end.map(&:first)

        ohi_jsons.each_with_index do |ohi_result, index|
          ohi_pdf = ohi_pdf_paths[index]
          next unless ohi_pdf

          clean_name = File.basename(ohi_pdf).gsub('-tmp', '')
          additional[clean_name] = (additional[clean_name] || {}).merge(
            'meta-jsonfile' => File.basename(ohi_result[:path])
          )
        end
      end

      def parse_docs_only_payload
        parsed_form_data = JSON.parse(params.to_json)
        parsed_form_data['form_number'] ||= '10-10D-EXTENDED'
        parsed_form_data
      end

      def process_docs_only_resubmission(parsed_form_data)
        resolve_supplemental_form_number!(parsed_form_data)
        form_id = form_id_for_form_number(parsed_form_data['form_number'])
        Datadog::Tracing.active_trace&.set_tag('form_id', form_id)

        response = handle_file_uploads_wrapper(form_id, parsed_form_data)
        mark_docs_only_evidence_submissions_received(parsed_form_data) if successful_upload_response?(response[:status])
        response
      end

      def ensure_docs_only_resubmission_enabled(parsed_form_data)
        return if docs_only_resubmission_flow_enabled?(parsed_form_data)

        raise ArgumentError, 'documents-only resubmission flow is not enabled for this payload'
      end

      def form_id_for_form_number(form_number)
        form_id = FORM_NUMBER_MAP[form_number]
        return form_id if form_id.present?

        raise ArgumentError, "Unsupported form number: #{form_number}"
      end

      def handle_docs_only_resubmission_argument_error(error)
        message = error.message
        Rails.logger.error("Validation error in CHAMPVA docs-only resubmission: #{message}")
        render json: { error_message: message }, status: :unprocessable_entity
      end

      def handle_docs_only_resubmission_unexpected_error(error)
        message = error.message
        Rails.logger.error("Docs-only resubmission error: #{message}")
        Rails.logger.error(error.backtrace.join("\n"))
        render json: { error_message: "Error: #{message}" }, status: :internal_server_error
      end

      def persist_claim_evidence_submission(attachment)
        raw_claim_id = params[:claim_id]
        return if raw_claim_id.blank?

        logger = Rails.logger
        claim_id = claim_id_for_evidence_submission(raw_claim_id, logger)
        return if claim_id.blank?

        user_account = user_account_for_evidence_submission(logger)
        return if user_account.blank?

        file_name = uploaded_file_name_for_evidence_submission(attachment, logger)
        return if file_name.blank?

        create_evidence_submission_record(claim_id, user_account, file_name)
      rescue ArgumentError, TypeError
        # `claim_id` is optional for legacy upload paths.
        nil
      rescue => e
        logger&.error("Failed to persist CHAMPVA evidence submission: #{e.class} #{e.message}")
        nil
      end

      def claim_id_for_evidence_submission(raw_claim_id, logger)
        claim_id = resolve_claim_record_ids(raw_claim_id).first
        return claim_id if claim_id.present?

        logger.warn('Skipping CHAMPVA evidence submission persistence: provided claim_id was unresolvable')
        nil
      end

      def user_account_for_evidence_submission(logger)
        user_account = current_user_account_for_evidence_submission
        return user_account if user_account.present?

        logger.warn('Skipping CHAMPVA evidence submission persistence: missing user_account')
        nil
      end

      def uploaded_file_name_for_evidence_submission(attachment, logger)
        file_name = uploaded_file_name(params['file'], attachment)
        return file_name if file_name.present?

        logger.warn('Skipping CHAMPVA evidence submission persistence: missing file_name')
        nil
      end

      def create_evidence_submission_record(claim_id, user_account, file_name)
        EvidenceSubmission.create(
          claim_id:,
          tracked_item_id: nil,
          upload_status: BenefitsDocuments::Constants::UPLOAD_STATUS[:CREATED],
          user_account:,
          template_metadata: evidence_submission_template_metadata(file_name).to_json
        )
      end

      def evidence_submission_template_metadata(file_name)
        document_type = params[:attachment_id].presence || 'Supporting document'

        {
          personalisation: {
            document_type:,
            file_name:,
            obfuscated_file_name: BenefitsDocuments::Utilities::Helpers.generate_obscured_file_name(file_name),
            date_submitted: BenefitsDocuments::Utilities::Helpers.format_date_for_mailers(Time.zone.now),
            date_failed: nil
          }
        }
      end

      def successful_upload_response?(status)
        status.to_i == 200
      end

      def mark_docs_only_evidence_submissions_received(parsed_form_data)
        claim_ids = resolve_claim_record_ids(parsed_form_data['claim_id'])
        return if claim_ids.blank?

        submitted_file_name_counts = submitted_supporting_doc_file_name_counts(parsed_form_data)
        return if submitted_file_name_counts.blank?

        pending_submissions = pending_evidence_submissions_for_claim_ids(claim_ids)

        updated_count = 0
        pending_submissions.each do |submission|
          updated_count += 1 if mark_submission_received_if_matches(submission, submitted_file_name_counts)
        end

        Rails.logger.info(
          "Marked #{updated_count} CHAMPVA evidence submission(s) as SUCCESS for claim_ids=#{claim_ids.join(',')}"
        )
      end

      def submitted_supporting_doc_file_name_counts(parsed_form_data)
        Array(parsed_form_data['supporting_docs'])
          .filter_map { |doc| normalize_file_name(doc['name']) }
          .tally
      end

      def pending_evidence_submissions_for_claim_ids(claim_ids)
        pending_statuses = [
          BenefitsDocuments::Constants::UPLOAD_STATUS[:CREATED],
          BenefitsDocuments::Constants::UPLOAD_STATUS[:QUEUED],
          BenefitsDocuments::Constants::UPLOAD_STATUS[:PENDING]
        ]

        EvidenceSubmission.where(claim_id: claim_ids, upload_status: pending_statuses)
                          .where('created_at >= ?', 2.days.ago)
                          .order(created_at: :desc)
                          .limit(50)
      end

      def resolve_claim_record_ids(raw_claim_id)
        claim_id = raw_claim_id.to_s
        return [] if claim_id.blank?
        return [Integer(claim_id, 10)] if claim_id.match?(/\A\d+\z/)

        IvcChampvaForm.where(form_uuid: claim_id).order(:created_at).pluck(:id)
      end

      def mark_submission_received_if_matches(submission, submitted_file_name_counts)
        file_name = submission_file_name(submission)
        remaining = submitted_file_name_counts[file_name].to_i
        return false if file_name.blank? || remaining <= 0

        submission.update!(
          upload_status: BenefitsDocuments::Constants::UPLOAD_STATUS[:SUCCESS],
          acknowledgement_date: Time.current
        )
        submitted_file_name_counts[file_name] = remaining - 1
        true
      rescue JSON::ParserError, TypeError
        false
      end

      def submission_file_name(submission)
        metadata = JSON.parse(submission.template_metadata)
        normalize_file_name(metadata.dig('personalisation', 'file_name'))
      end

      def normalize_file_name(file_name)
        file_name.to_s.strip.downcase.presence
      end

      def resolve_claim_record_id(raw_claim_id)
        claim_id = raw_claim_id.to_s
        return nil if claim_id.blank?
        return Integer(claim_id, 10) if claim_id.match?(/\A\d+\z/)

        IvcChampvaForm.where(form_uuid: claim_id).order(updated_at: :desc).limit(1).pick(:id)
      rescue ArgumentError, TypeError
        nil
      end

      def current_user_account_for_evidence_submission
        return nil if @current_user&.user_account_uuid.blank?

        UserAccount.find_by(id: @current_user.user_account_uuid)
      end

      def uploaded_file_name(source_file, attachment)
        attachment_file = attachment.file
        return source_file.original_filename if source_file.respond_to?(:original_filename)
        return attachment_file.original_filename if attachment_file.respond_to?(:original_filename)
        return attachment_file.metadata['filename'] if attachment_file.respond_to?(:metadata)
        return File.basename(attachment_file.path) if attachment_file.respond_to?(:path)

        nil
      end

      def content_type_from_extension(ext)
        case ext.downcase
        when '.pdf'
          'application/pdf'
        when '.jpg', '.jpeg'
          'image/jpeg'
        when '.png'
          'image/png'
        when '.heic'
          'image/heic'
        when '.heif'
          'image/heif'
        else
          'application/octet-stream'
        end
      end

      ##
      # Converts an uploaded file to PDF if it's an image. Returns the file unchanged if already a PDF.
      #
      # @param uploaded_file [ActionDispatch::Http::UploadedFile] The file to convert
      # @return [ActionDispatch::Http::UploadedFile] The converted PDF or original file
      # @raise [StandardError] If PDF conversion fails
      def convert_to_pdf(uploaded_file)
        Datadog::Tracing.trace('IVC Champva Forms - Convert to PDF') do
          return uploaded_file if uploaded_file.content_type == 'application/pdf'

          tempfile = IvcChampva::PdfConverter.new(uploaded_file).convert_to_tempfile
          pdf_filename = uploaded_file.original_filename.sub(/\.[^.]+\z/, '.pdf')

          ActionDispatch::Http::UploadedFile.new(
            tempfile:,
            filename: pdf_filename,
            type: 'application/pdf'
          )
        end
      end

      def applicants_with_ohi(applicants)
        applicants.select do |item|
          health_insurance = item['health_insurance']
          medicare = item['medicare']

          (health_insurance.is_a?(Array) && health_insurance.any?) ||
            (medicare.is_a?(Array) && medicare.any?)
        end
      end

      ##
      # Generates OHI form instances for a single applicant.
      # Creates one form per 2 health insurance policies to handle overflow
      # when an applicant has more than 2 policies.
      #
      # @param applicant [Hash] Applicant data containing health_insurance array
      # @param form_data [Hash] Complete form submission data (form-level fields)
      # @return [Array<IvcChampva::VHA107959cRev2025>] Array of form instances
      def generate_ohi_form(applicant, form_data)
        forms = []
        health_insurance = applicant['health_insurance'] || [{}]

        health_insurance.each_slice(2) do |policies_pair|
          applicant_data = form_data.except('applicants', 'raw_data', 'medicare').merge(applicant)
          applicant_data['form_number'] = '10-7959C'

          if Flipper.enabled?(:champva_form_10_7959c_rev2025, @current_user)
            # NEW: Pass health_insurance array, constructor handles flattening
            applicant_data['health_insurance'] = policies_pair
            forms << IvcChampva::VHA107959cRev2025.new(applicant_data)
          else
            # OLD: Manually map policies to applicant_primary_*/applicant_secondary_* fields
            applicant_with_mapped_policies = map_policies_to_applicant(policies_pair, applicant_data)
            form = IvcChampva::VHA107959cRev2025.new(applicant_with_mapped_policies)
            form.data['form_number'] = '10-7959C'
            forms << form
          end
        end

        forms
      end

      ##
      # Sets the primary/secondary health insurance properties on the provided
      # applicant based on a pair of policies. This is so that we can automatically
      # get the keys/values needed to generate overflow OHI forms in the event
      # an applicant is associated with > 2 health insurance policies
      #
      # @param [Array<Hash>] policies Array of hashes representing insurance policies.
      # @param [Hash] applicant Hash representing an applicant object from a 10-10d/10-7959c form
      #
      # @returns [Hash] Updated applicant hash with the primary/secondary insurances mapped
      # so an OHI (10-7959c) PDF can be stamped with this info
      #
      def map_policies_to_applicant(policies, applicant)
        # Create a copy of the applicant hash to avoid modifying the original
        updated_applicant = Marshal.load(Marshal.dump(applicant))

        # Map primary and secondary insurance policies
        map_primary_policy_to_applicant(policies[0], updated_applicant) if policies&.[](0)
        map_secondary_policy_to_applicant(policies[1], updated_applicant) if policies&.[](1)

        updated_applicant
      end

      ##
      # Maps primary insurance policy fields to the applicant hash
      #
      # @param [Hash] policy Primary insurance policy data
      # @param [Hash] applicant Applicant hash to update
      #
      def map_primary_policy_to_applicant(policy, applicant)
        applicant['applicant_primary_provider'] = policy['provider']
        applicant['applicant_primary_effective_date'] = policy['effective_date']
        applicant['applicant_primary_expiration_date'] = policy['expiration_date']
        applicant['applicant_primary_through_employer'] = policy['through_employer']
        applicant['applicant_primary_insurance_type'] = policy['insurance_type']
        applicant['applicant_primary_eob'] = policy['eob']
        applicant['primary_medigap_plan'] = policy['medigap_plan']
        applicant['primary_additional_comments'] = policy['additional_comments']
      end

      ##
      # Maps secondary insurance policy fields to the applicant hash
      #
      # @param [Hash] policy Secondary insurance policy data
      # @param [Hash] applicant Applicant hash to update
      #
      def map_secondary_policy_to_applicant(policy, applicant)
        applicant['applicant_secondary_provider'] = policy['provider']
        applicant['applicant_secondary_effective_date'] = policy['effective_date']
        applicant['applicant_secondary_expiration_date'] = policy['expiration_date']
        applicant['applicant_secondary_through_employer'] = policy['through_employer']
        applicant['applicant_secondary_insurance_type'] = policy['insurance_type']
        applicant['applicant_secondary_eob'] = policy['eob']
        applicant['secondary_medigap_plan'] = policy['medigap_plan']
        applicant['secondary_additional_comments'] = policy['additional_comments']
      end

      def fill_ohi_and_return_path(form)
        # Generate PDF
        filler = IvcChampva::PdfFiller.new(form_number: 'vha_10_7959c_rev2025', form:, uuid: form.uuid)
        # Results in a file path, which is returned
        if @current_user
          filler.generate(@current_user.loa[:current])
        else
          filler.generate
        end
      end

      def create_custom_attachment(form, file_path, attachment_id)
        # Create attachment
        attachment = PersistentAttachments::MilitaryRecords.new(form_id: form.form_id)

        begin
          File.open(file_path, 'rb') do |file|
            attachment.file = file
            attachment.save
          end

          # Clean up the file
          FileUtils.rm_f(file_path)

          IvcChampva::Attachments.serialize_attachment(attachment, attachment_id)
        rescue => e
          Rails.logger.error "Failed to process new custom attachment: #{e.message}"
          FileUtils.rm_f(file_path)
          raise
        end
      end

      # Probably doesn't need to be its own method, but trying to keep methods
      # short by splitting out as much as possible
      def add_supporting_doc(form_data, doc)
        form_data['supporting_docs'] ||= []
        form_data['supporting_docs'] << doc
      end

      # Probably doesn't need to be its own method, but trying to keep methods
      # short by splitting out as much as possible
      def log_error_and_respond(message, exception = nil)
        Rails.logger.error message
        Rails.logger.error exception.backtrace.join("\n") if exception
        render json: { error_message: message }, status: :internal_server_error
      end

      ##
      # Wraps handle_uploads and includes retry logic when file uploads get non-200s.
      #
      # @param [String] form_id The ID of the current form, e.g., 'vha_10_10d' (see FORM_NUMBER_MAP)
      # @param [Array<String>] file_paths The file paths of the files to upload
      # @param [Hash] metadata The metadata for the form
      # @param [Hash] parsed_form_data Optional original form data for storage
      #
      # @return [Array<Integer, String>] An array with 1 or more http status codes
      #   and an array with 1 or more message strings.
      # rubocop:disable Metrics/MethodLength
      def handle_file_uploads(form_id, file_paths, metadata, parsed_form_data = nil)
        Datadog::Tracing.trace('IVC Champva Forms - Upload Files') do
          on_failure = lambda do |e, attempt|
            Rails.logger.error "Error handling file uploads (attempt #{attempt}): #{e.message}"
            PersonalInformationLog.create(
              data: parsed_form_data,
              error_class: 'IvcChampva::V1::UploadsController#handle_file_uploads'
            )
          end

          # set default values for statuses and error_messages to avoid nil reference errors
          statuses = [500]
          error_messages = ['Server error occurred']

          IvcChampva::Retry.do(1, retry_on: RETRY_ERROR_CONDITIONS, on_failure:) do
            options = { insert_db_row: true, current_user: @current_user, parsed_form_data: }
            uploader = FileUploader.new(form_id, metadata, file_paths, **options)
            hu_result = uploader.handle_uploads
            # convert [[200, nil], [400, 'error']] -> [200, 400] and [nil, 'error'] arrays
            statuses, error_messages = hu_result[0].is_a?(Array) ? hu_result.transpose : hu_result.map { |i| Array(i) }

            # Since some or all of the files failed to upload to S3, trigger retry
            raise StandardError, error_messages if error_messages.compact.length.positive?
          end

          [statuses, error_messages]
        ensure
          cleanup_supporting_doc_working_files(file_paths)
        end
      end
      # rubocop:enable Metrics/MethodLength

      def cleanup_supporting_doc_working_files(file_paths)
        Array(file_paths).each do |path|
          next if path.blank?

          file_name = File.basename(path)
          next unless file_name.include?('_supporting_doc-')

          tmp_prefix = Rails.root.join('tmp').to_s
          next unless path.start_with?(tmp_prefix)

          FileUtils.rm_f(path)
        end
      end

      def should_retry?(error_message_downcase, attempt, max_attempts = 1)
        error_conditions = [
          'failed to generate',
          'no such file',
          'an error occurred while verifying stamp:',
          'unable to find file'
        ]

        error_conditions.any? { |condition| error_message_downcase.include?(condition) } && attempt <= max_attempts
      end

      def get_file_paths_and_metadata(parsed_form_data)
        Datadog::Tracing.trace('IVC Champva Forms - Get File Paths and Metadata and Other Work') do
          if docs_only_resubmission_flow_enabled?(parsed_form_data)
            return get_docs_only_resubmission_file_paths_and_metadata(parsed_form_data)
          end

          base_form_id = get_form_id
          form = IvcChampva::FormVersionManager.create_form_instance(base_form_id, parsed_form_data, @current_user)
          track_form_submission_metrics(form)

          attachment_ids, stamped_page = form.prepare_submission_data(
            base_form_id, parsed_form_data, @current_user, controller: self
          )

          file_paths, metadata, legacy_form_id = generate_pdf_and_assemble_paths(form, attachment_ids, stamped_page)

          append_ves_json_files(form, parsed_form_data, [file_paths, attachment_ids, metadata, legacy_form_id])

          [file_paths, metadata.merge({ 'attachment_ids' => attachment_ids })]
        end
      end

      def generate_pdf_and_assemble_paths(form, attachment_ids, stamped_page)
        actual_form_id = form.form_id
        legacy_form_id = IvcChampva::FormVersionManager.get_legacy_form_id(actual_form_id)

        filler = IvcChampva::PdfFiller.new(form_number: actual_form_id, form:, uuid: form.uuid, name: legacy_form_id)
        file_path = @current_user ? filler.generate(@current_user.loa[:current]) : filler.generate

        metadata = form.validated_metadata
        file_paths = form.handle_attachments(file_path)

        if stamped_page
          file_paths << stamped_page[:file_path]
          attachment_ids << stamped_page[:attachment_id]
        end

        [file_paths, metadata, legacy_form_id]
      end

      def docs_only_resubmission?(parsed_form_data)
        return false unless DOCS_ONLY_RESUBMISSION_FORM_NUMBERS.include?(parsed_form_data['form_number'].to_s)

        submission_type = parsed_form_data['submission_type'].to_s.strip.downcase
        DOCS_ONLY_RESUBMISSION_SUBMISSION_TYPES.include?(submission_type)
      end

      def docs_only_resubmission_flow_enabled?(parsed_form_data)
        docs_only_resubmission_flow(parsed_form_data) != :none
      end

      def docs_only_resubmission_flow(parsed_form_data)
        if cst_docs_only_resubmission_flow_enabled?(parsed_form_data)
          :cst
        elsif form_submission_docs_only_resubmission_flow_enabled?(parsed_form_data)
          :form_submission
        else
          :none
        end
      end

      def cst_docs_only_resubmission_flow_enabled?(parsed_form_data)
        docs_only_resubmission?(parsed_form_data) &&
          parsed_form_data['claim_id'].present? &&
          Flipper.enabled?(:champva_cst_file_uploader_docs_only_resubmission, @current_user)
      end

      def form_submission_docs_only_resubmission_flow_enabled?(parsed_form_data)
        docs_only_resubmission?(parsed_form_data) &&
          parsed_form_data['claim_id'].blank? &&
          Flipper.enabled?(:form1010d_enhanced_flow_enabled, @current_user)
      end

      def validate_docs_only_resubmission!(parsed_form_data)
        if parsed_form_data['claim_id'].blank?
          raise ArgumentError, 'claim_id is required for documents-only resubmission'
        end
        if parsed_form_data['submission_type'].blank?
          raise ArgumentError, 'submission_type is required for documents-only resubmission'
        end

        docs = parsed_form_data['supporting_docs']
        raise ArgumentError, 'supporting documents are required for documents-only resubmission' if docs.blank?

        docs.each_with_index do |doc, index|
          validate_docs_only_supporting_doc(doc, index)
        end
      end

      def validate_docs_only_supporting_doc(doc, index)
        raise ArgumentError, "supporting_docs[#{index}] must be an object" unless doc.respond_to?(:[])

        file_name = doc['name']
        raise ArgumentError, "supporting_docs[#{index}] is missing name" if file_name.blank?

        confirmation_code = doc['confirmation_code']
        raise ArgumentError, "supporting_docs[#{index}] is missing confirmation_code" if confirmation_code.blank?

        return if PersistentAttachments::MilitaryRecords.exists?(guid: confirmation_code)

        raise ArgumentError,
              "supporting_docs[#{index}] confirmation_code could not be resolved to an existing attachment"
      end

      def hydrate_docs_only_resubmission_data(parsed_form_data)
        source_form = IvcChampvaForm.where(form_uuid: parsed_form_data['claim_id'].to_s).order(updated_at: :desc).first
        raise ArgumentError, 'claim_id could not be resolved to an existing CHAMPVA form' if source_form.blank?

        source_payload = source_form_payload(source_form)
        hydrate_certification_fields(parsed_form_data, source_payload)
        hydrate_primary_contact_info(parsed_form_data, source_form)
        hydrate_veteran_info(parsed_form_data, source_form, source_payload)
        hydrate_applicants(parsed_form_data, source_form, source_payload)
      end

      def hydrate_certification_fields(parsed_form_data, source_payload)
        parsed_form_data['certifier_role'] ||= source_payload['certifier_role'] || source_payload['certifierRole']
        parsed_form_data['statement_of_truth_signature'] ||=
          source_payload['statement_of_truth_signature'] || source_payload['statementOfTruthSignature']

        parsed_form_data['certification'] ||= {}
        parsed_form_data['certification']['date'] ||=
          source_payload.dig('certification', 'date') || source_payload['certification_date']
      end

      def hydrate_primary_contact_info(parsed_form_data, source_form)
        primary_contact_info = parsed_form_data['primary_contact_info'] ||= {}
        primary_contact_info['email'] ||= source_form.email

        name = primary_contact_info['name'] ||= {}
        name['first'] ||= source_form.first_name
        name['last'] ||= source_form.last_name
      end

      def hydrate_veteran_info(parsed_form_data, source_form, source_payload)
        veteran = parsed_form_data['veteran'] ||= {}
        source_veteran = source_payload['veteran'] || {}

        full_name = veteran['full_name'] ||= {}
        full_name['first'] ||= source_form.first_name
        full_name['last'] ||= source_form.last_name
        full_name['middle'] ||= source_veteran.dig('full_name', 'middle')
        full_name['suffix'] ||= source_veteran.dig('full_name', 'suffix')

        veteran['ssn_or_tin'] ||= source_veteran['ssn_or_tin']
        veteran['date_of_birth'] ||= source_veteran['date_of_birth']

        veteran['ssn_or_tin'] ||= source_veteran['ssn_or_tin'] || source_veteran['ssnOrTin']
        veteran['date_of_birth'] ||= source_veteran['date_of_birth'] || source_veteran['dateOfBirth']

        address = veteran['address'] ||= {}
        address['country'] ||= 'USA'
        address['postal_code'] ||= '00000'
      end

      def source_form_payload(source_form)
        payload = source_form.request_json
        return payload if payload.is_a?(Hash)
        return JSON.parse(payload) if payload.is_a?(String)

        {}
      rescue JSON::ParserError
        {}
      end

      def hydrate_applicants(parsed_form_data, source_form, source_payload)
        source_applicants = Array(source_payload['applicants'])

        if parsed_form_data['applicants'].blank?
          parsed_form_data['applicants'] = source_applicants.presence || [default_applicant(source_form)]
          return
        end

        parsed_form_data['applicants'] = Array(parsed_form_data['applicants']).map do |applicant|
          hydrate_applicant(applicant, source_applicants)
        end
      end

      def default_applicant(source_form)
        {
          'applicant_name' => {
            'first' => source_form.first_name,
            'last' => source_form.last_name
          },
          'vet_relationship' => 'spouse'
        }
      end

      def hydrate_applicant(applicant, source_applicants)
        applicant_name = applicant['applicant_name'] || applicant['applicantName'] || {}
        applicant['applicant_name'] ||= applicant['applicantName'] if applicant['applicantName'].present?
        match = matching_source_applicant(applicant_name, source_applicants)
        match ||= source_applicants.first if source_applicants.size == 1
        return applicant unless match

        applicant['applicant_dob'] ||= match['applicant_dob'] || match['applicantDob']
        applicant['applicant_member_number'] ||= match['applicant_member_number'] || match['applicantMemberNumber']

        applicant
      end

      def matching_source_applicant(applicant_name, source_applicants)
        first = applicant_name['first'].to_s.strip.downcase
        last = applicant_name['last'].to_s.strip.downcase
        return nil if first.blank? || last.blank?

        source_applicants.find do |candidate|
          candidate_name = candidate['applicant_name'] || candidate['applicantName'] || {}
          candidate_first = candidate_name['first'].to_s.strip.downcase
          candidate_last = candidate_name['last'].to_s.strip.downcase
          candidate_first == first && candidate_last == last
        end
      end

      # rubocop:disable Metrics/MethodLength
      def get_docs_only_resubmission_file_paths_and_metadata(parsed_form_data)
        Datadog::Tracing.trace('IVC Champva Forms - Get docs-only paths and metadata') do
          base_form_id = form_id_for_form_number(parsed_form_data['form_number'])
          form = IvcChampva::FormVersionManager.create_form_instance(base_form_id, parsed_form_data, @current_user)
          track_form_submission_metrics(form)

          attachment_ids = form.supporting_document_ids(parsed_form_data)
          if attachment_ids.blank?
            raise ArgumentError, 'supporting documents must resolve to at least one attachment id for upload'
          end

          merge_fields = {
            'submissionType' => parsed_form_data['submission_type'].to_s,
            'docType' => "#{parsed_form_data['form_number']}-#{parsed_form_data['submission_type'].to_s.upcase}",
            'supportingDocApplicants' => supporting_document_applicants(parsed_form_data).to_json,
            'standalone-flag' => 'true'
          }
          merge_fields['uuid'] = parsed_form_data['claim_id'] if parsed_form_data['claim_id'].present?
          raw_metadata = form.metadata.merge(merge_fields)
          if parsed_form_data['submission_type'].to_s.casecmp('enrollment').zero?
            backfill_enrollment_metadata!(raw_metadata)
          end
          metadata = IvcChampva::MetadataValidator.validate(raw_metadata)
          file_paths = docs_only_resubmission_supporting_paths_from_form(form)

          [file_paths, metadata.merge({ 'attachment_ids' => attachment_ids })]
        end
      end
      # rubocop:enable Metrics/MethodLength

      def resolve_supplemental_form_number!(parsed_form_data)
        return if parsed_form_data['submission_type'].blank?
        return unless DOCS_ONLY_RESUBMISSION_FORM_NUMBERS.include?(parsed_form_data['form_number'])

        parsed_form_data['form_number'] = '10-10D-SUPPLEMENTAL'
      end

      def supporting_document_applicants(parsed_form_data)
        cached_uploads = []
        parsed_form_data['supporting_docs']&.each do |doc|
          record = PersistentAttachments::MilitaryRecords.find_by(guid: doc['confirmation_code'])
          cached_uploads << {
            attachment_id: doc['attachment_id'],
            confirmation_code: doc['confirmation_code'],
            applicants: Array(doc['applicants']).compact,
            created_at: record&.created_at
          }
        end

        cached_uploads
          .sort_by { |upload| upload[:created_at] || Time.zone.at(0) }
          .map { |upload| upload.except(:created_at) }
      end

      def backfill_enrollment_metadata!(metadata)
        metadata['veteranFirstName'] ||= metadata['sponsorFirstName']
        metadata['veteranMiddleName'] ||= metadata['sponsorMiddleName']
        metadata['veteranLastName'] ||= metadata['sponsorLastName']
      end

      def docs_only_resubmission_supporting_paths_from_form(form)
        placeholder_path = IvcChampva::Attachments.get_blank_page
        begin
          file_paths = form.handle_attachments(placeholder_path)
          file_paths.shift

          if file_paths.empty?
            raise ArgumentError, 'no supporting document files could be resolved for documents-only resubmission'
          end

          file_paths
        ensure
          FileUtils.rm_f(placeholder_path)
        end
      end

      def track_form_submission_metrics(form)
        form.track_user_identity
        form.track_current_user_loa(@current_user)
        form.track_email_usage
        if Flipper.enabled?(:champva_update_datadog_tracking, @current_user) && form.respond_to?(:track_submission)
          form.track_submission(@current_user)
        end
      end

      def get_form_id
        form_number = params[:form_number]
        raise 'Missing/malformed form_number in params' unless form_number

        FORM_NUMBER_MAP[form_number]
      end

      def build_json(statuses, error_message)
        if statuses.nil?
          return { json: { error_message: 'An unknown error occurred while uploading document(s).' }, status: 500 }
        end

        unique_statuses = statuses.uniq

        if unique_statuses == [200]
          { json: {}, status: 200 }
        elsif unique_statuses.include? 400
          { json: { error_message: error_message ||
            'An unknown error occurred while uploading some documents.' }, status: 400 }
        else
          { json: { error_message: 'An unknown error occurred while uploading document(s).' }, status: 500 }
        end
      end

      def authenticate
        super
      rescue Common::Exceptions::Unauthorized
        Rails.logger.info(
          'IVC Champva - unauthenticated user submitting form',
          { form_number: params[:form_number] }
        )
      end

      def submit_supporting_documents_params
        params.permit(:file, :password, :form_id, :attachment_id)
      end
    end
  end
end
# rubocop:enable Metrics/ClassLength
