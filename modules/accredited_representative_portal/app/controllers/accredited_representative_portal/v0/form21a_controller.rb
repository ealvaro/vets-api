# frozen_string_literal: true

module AccreditedRepresentativePortal
  module V0
    class Form21aController < ApplicationController
      include AccreditedRepresentativePortal::V0::Form21aUploadConcern
      skip_after_action :verify_pundit_authorization

      class SchemaValidationError < StandardError
        attr_reader :errors

        def initialize(errors)
          @errors = errors
          super("Validation failed: #{errors}")
        end
      end

      FORM_ID = '21a'
      RESUBMITTABLE_STATUS = 'resubmittable'
      RESUBMITTABLE_MESSAGE = 'We saved your application. Please try submitting Form 21a again.'

      # NOTE: The order of before_action calls is important here.
      before_action :feature_enabled, :loa3_user?
      before_action :parse_request_body, :validate_form, only: [:submit]

      def background_detail_upload
        file = params[:file]
        return render json: { errors: 'file is required' }, status: :bad_request if file.blank?

        details_slug = params[:details_slug]
        log_detail_upload_received(details_slug)

        form_attachment = AccreditedRepresentativePortal::Form21aAttachment.new
        form_attachment.set_file_data!(file)
        form_attachment.save!
        update_in_progress_form(details_slug, file, form_attachment)

        render_detail_upload_success(form_attachment, file)
      rescue Common::Exceptions::UnprocessableEntity => e
        handle_unprocessable_detail_upload(e, details_slug)
      rescue ActiveRecord::RecordInvalid => e
        handle_invalid_detail_upload_record(e, details_slug)
      end

      def submit
        form_hash = JSON.parse(@parsed_request_body)

        response = AccreditationService.submit_form21a([form_hash], @current_user&.uuid)

        handle_post_submission(response) if response.success?

        render_ogc_service_response(response)
      rescue Faraday::TimeoutError, Faraday::ConnectionFailed => e
        handle_submit_network_error(e)
      rescue => e
        handle_submit_unexpected_error(e)
      end

      private

      attr_reader :parsed_request_body

      def schema
        VetsJsonSchema::SCHEMAS[FORM_ID.upcase]
      end

      def current_in_progress_form_or_routing_error
        current_in_progress_form || routing_error
      end

      def current_in_progress_form
        InProgressForm.form_for_user(FORM_ID, current_user)
      end

      def log_detail_upload_received(details_slug)
        Rails.logger.info(
          "Form21aController: Received details upload for slug=#{details_slug} " \
          "user_uuid=#{current_user&.uuid}"
        )
      end

      def render_detail_upload_success(form_attachment, file)
        render json: {
          data: {
            attributes: {
              errorMessage: '',
              confirmationCode: form_attachment.guid,
              name: file.original_filename,
              size: file.size,
              type: file.content_type
            }
          }
        }, status: :ok
      end

      def handle_unprocessable_detail_upload(error, details_slug)
        detail = error.errors.first.detail
        Rails.logger.error(
          "Form21aController: File upload unprocessable for user_uuid=#{current_user&.uuid} " \
          "details_slug=#{details_slug} error=#{detail}"
        )
        render json: { errors: detail }, status: :unprocessable_entity
      end

      def handle_invalid_detail_upload_record(error, details_slug)
        Rails.logger.error(
          "Form21aController: details upload failed validation for user_uuid=#{current_user&.uuid} " \
          "details_slug=#{details_slug} errors=#{error.record.errors.full_messages.join(', ')}"
        )
        render json: { errors: 'Unable to store document' }, status: :unprocessable_entity
      end

      def handle_post_submission(response)
        enqueue_document_uploads(response)
        destroy_in_progress_form
      rescue => e
        Rails.logger.error(
          "Form21aController: Post-submission error: #{e.class} #{e.message} " \
          "for user_uuid=#{@current_user&.uuid}"
        )
      end

      def handle_submit_network_error(error)
        Rails.logger.error(
          "Form21aController: Network error: #{error.class} #{error.message} for user_uuid=#{@current_user&.uuid}"
        )

        render json: resubmittable_error_response('Service temporarily unavailable'), status: :service_unavailable
      end

      def handle_submit_unexpected_error(error)
        Rails.logger.error(
          "Form21aController: Unexpected error: #{error.class} #{error.message} for user_uuid=#{@current_user&.uuid}"
        )
        render json: { errors: 'Internal server error' }, status: :internal_server_error
      end

      def update_in_progress_form(details_slug, file, form_attachment)
        in_progress_form = current_in_progress_form_or_routing_error
        documents_key = documents_key_for(details_slug)
        form_data = JSON.parse(in_progress_form.form_data.presence || '{}')

        form_data[documents_key] ||= []

        form_data[documents_key] << {
          'name' => file.original_filename,
          'confirmationCode' => form_attachment.guid,
          'size' => file.size,
          'type' => file.content_type
        }

        in_progress_form.update!(form_data: form_data.to_json)
      end

      def enqueue_document_uploads(response)
        application_id = response.body.dig('uploaded', 0, 'application', 'id')
        in_progress_form = InProgressForm.form_for_user(FORM_ID, @current_user)

        if application_id.blank?
          Rails.logger.error(
            "Form21aController: Missing application id in GCLAWS response for user_uuid=#{@current_user&.uuid}"
          )
          return
        end

        if in_progress_form.blank?
          Rails.logger.warn(
            'Form21aController: No in-progress form found after successful Form 21a submission ' \
            "for user_uuid=#{@current_user&.uuid} application_id=#{application_id}"
          )
          return
        end

        AccreditedRepresentativePortal::Form21aDocumentUploadService.enqueue_uploads(
          in_progress_form:,
          application_id:
        )
      end

      def destroy_in_progress_form
        InProgressForm.form_for_user(FORM_ID, @current_user)&.destroy!
      rescue ActiveRecord::ActiveRecordError => e
        Rails.logger.error(
          'Form21aController: Failed to destroy in-progress form after successful Form 21a submission ' \
          "for user_uuid=#{@current_user&.uuid}. Error: #{e.class} - #{e.message}"
        )
      end

      # Checks if the feature flag accredited_representative_portal_form_21a is enabled or not
      def feature_enabled
        routing_error unless Flipper.enabled?(:accredited_representative_portal_form_21a)
      end

      def loa3_user?
        routing_error unless current_user.loa3?
      end

      # Parses the raw request body as JSON and assigns it to an instance variable.
      # Renders a bad request response if the JSON is invalid.
      def parse_request_body
        raw = request.raw_post
        body = JSON.parse(raw)
        form_json = body.dig('form21aSubmission', 'form')
        raise JSON::ParserError, 'Missing or invalid form21aSubmission.form' unless form_json

        form_data = JSON.parse(form_json)
        form_data['icnNo'] = @current_user.icn if @current_user&.icn.present?
        form_data['uId'] = @current_user.uuid if @current_user&.uuid.present?
        @parsed_request_body = form_data.to_json
      rescue JSON::ParserError
        handle_json_error
      end

      def validate_form
        errors = JSON::Validator.fully_validate(schema, @parsed_request_body)
        raise SchemaValidationError, errors if errors.any?
      rescue SchemaValidationError => e
        handle_json_error(e.errors.join(', ').squeeze(' '))
      end

      def handle_json_error(details = nil)
        error_message = 'Form21aController: Invalid JSON in request body for user ' \
                        "with user_uuid=#{@current_user&.uuid}."
        error_message += " Errors: #{details}" if details
        Rails.logger.error(error_message)

        response_error = details || 'Invalid JSON'
        render json: { errors: response_error }, status: :bad_request
      end

      def render_ogc_service_response(response)
        application_id = extract_application_id(response)
        return render_ogc_success_response(response, application_id) if response.success?
        return render_ogc_error_response(response, application_id) if response.body.present?

        render_ogc_blank_response
      end

      def render_ogc_success_response(response, application_id)
        Rails.logger.info(
          'Form21aController: Form 21a successfully submitted to OGC service ' \
          "by user with user_uuid=#{@current_user&.uuid} " \
          "status=#{response.status} application_id=#{application_id}"
        )
        render json: response.body, status: response.status
      end

      def render_ogc_error_response(response, application_id)
        Rails.logger.error(
          "Form21aController: OGC service returned error response (status=#{response.status}) " \
          "for user with user_uuid=#{@current_user&.uuid} application_id=#{application_id}"
        )

        render json: resubmittable_error_response(response.body), status: response.status
      end

      def render_ogc_blank_response
        Rails.logger.error(
          'Form21aController: Blank or unparsable response from external OGC service ' \
          "for user with user_uuid=#{@current_user&.uuid}"
        )

        render json: resubmittable_error_response('Blank or unparsable response from external OGC service'),
               status: :service_unavailable
      end

      def resubmittable_error_response(errors)
        {
          errors:,
          formSubmission: {
            status: RESUBMITTABLE_STATUS,
            message: RESUBMITTABLE_MESSAGE
          }
        }
      end

      def extract_application_id(response)
        response.body.dig('uploaded', 0, 'application', 'id') if response.body.is_a?(Hash)
      end
    end
  end
end
