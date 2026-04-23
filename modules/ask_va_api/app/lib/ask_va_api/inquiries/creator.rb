# frozen_string_literal: true

module AskVAApi
  module Inquiries
    class InquiriesCreatorError < StandardError
      attr_reader :context

      def initialize(message = nil, context: {})
        super(message)
        @context = context
      end

      def to_h
        {
          error: message,
          safe_fields: context[:safe_fields]
        }
      end

      def to_json(*)
        to_h.to_json(*)
      end
    end

    class Creator
      ENDPOINT = 'inquiries/new'
      SAFE_INQUIRY_FIELDS = %i[
        about_your_relationship_to_family_member
        contact_preference
        is_question_about_veteran_or_someone_else
        more_about_your_relationship_to_veteran
        relationship_to_veteran
        relationship_not_listed
        select_category
        select_subtopic
        select_topic
        their_relationship_to_veteran
        they_have_relationship_not_listed
        who_is_your_question_about
        your_location_of_residence
        your_role
        your_role_education
      ].freeze

      attr_reader :user, :service

      def initialize(user:, service: nil)
        @user = user
        @service = service || default_service
      end

      def call(inquiry_params:, request_id:)
        # Directly coupling to Datadog::Trace is a bad idea, but this is a targetted change.
        # This is a temporary solution to avoid the need for a full refactor of Logservice.
        Datadog::Tracing.trace('ask_va_api.inquiries.creator.call') do |span|
          safe_fields = log_safe_fields_from_inquiry(inquiry_params)
          span.set_tag('user.isAuthenticated', user.present?)
          span.set_tag('user.loa', user&.loa&.fetch(:current, nil))
          span.set_tag('inquiry', safe_fields)

          payload = build_payload(inquiry_params)
          if payload.key?(:LevelOfAuthentication)
            span.set_tag('Crm.LevelOfAuthentication', payload[:LevelOfAuthentication])
          end
          record_outbound_checkpoint(request_id:, payload:)
          post_data(payload, request_id:)
        rescue => e
          span.set_error(e)
          raise InquiriesCreatorError.new("InquiriesCreatorError: #{e.message}", context: { safe_fields: })
        end
      end

      private

      def log_safe_fields_from_inquiry(inquiry_params)
        # Logs suggest there may be an issue with inquiry_params.
        (inquiry_params || {}).slice(*SAFE_INQUIRY_FIELDS)
      end

      def default_service
        Crm::Service.new(icn: user&.icn)
      end

      def build_payload(inquiry_params)
        PayloadBuilder::InquiryPayload.new(inquiry_params:, user:).call
      end

      def post_data(payload, request_id:)
        response = service.call(endpoint: ENDPOINT, method: :put, payload:)
        record_crm_response_checkpoint(request_id:, payload: crm_response_checkpoint_payload(response))
        data = handle_response(response)
        log_inquiry_result_context(data)
        data
      end

      def crm_response_checkpoint_payload(response)
        return response if response.is_a?(Hash)

        # CRM failures arrive as Faraday::Response objects; normalize them into a hash before checkpointing.
        parsed_body = parse_response_body(response.body)
        return parsed_body if parsed_body.is_a?(Hash)

        fallback_crm_error_payload(response)
      end

      def parse_response_body(body)
        return body unless body.is_a?(String)

        JSON.parse(body, symbolize_names: true)
      rescue JSON::ParserError
        nil
      end

      def fallback_crm_error_payload(response)
        {
          Data: nil,
          Message: response.body.to_s,
          ExceptionOccurred: true,
          ExceptionMessage: response.body.to_s,
          StatusCode: response.status
        }
      end

      def log_inquiry_result_context(data)
        return if data.blank?

        context = { inquiry_number: data[:InquiryNumber] }

        Rails.logger.info('Inquiry Submission Result Context', context)
      end

      def handle_response(response)
        response.is_a?(Hash) ? response[:Data] : raise(InquiriesCreatorError, response.body)
      end

      def record_outbound_checkpoint(request_id:, payload:)
        Checkpoint::Outbound.new.call(
          request_id:,
          payload:
        )
      rescue => e
        Rails.logger.warn(
          'Failed to record Outbound checkpoint',
          {
            request_id:,
            checkpoint_type: 'outbound_submission',
            error_class: e.class.name,
            error_message: e.message
          }
        )
      end

      def record_crm_response_checkpoint(request_id:, payload:)
        Checkpoint::CrmResponse.new.call(
          request_id:,
          payload:
        )
      rescue => e
        Rails.logger.warn(
          'Failed to record CRM response checkpoint',
          {
            request_id:,
            checkpoint_type: 'crm_response',
            error_class: e.class.name,
            error_message: e.message
          }
        )
      end
    end
  end
end
