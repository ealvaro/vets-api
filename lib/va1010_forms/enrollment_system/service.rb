# frozen_string_literal: true

require 'benchmark'
require 'common/client/base'
require 'hca/configuration'
require 'hca/overrides_parser'

module VA1010Forms
  module EnrollmentSystem
    class Service < Common::Client::Base
      include ActionView::Helpers::NumberHelper

      configuration HCA::Configuration

      # @param [Hash] user_identifier
      # @example { 'icn' => user.icn, 'edipi' => user.edipi }
      def initialize(user_identifier = nil)
        super()
        @user_identifier = user_identifier
      end

      def submit(parsed_form, form_id)
        formatted = HCA::EnrollmentSystem.veteran_to_save_submit_form(
          parsed_form,
          @user_identifier,
          form_id
        )
        submission_body = submission_body(formatted)
        response = perform(:post, '', submission_body)

        root = response.body.locate('S:Envelope/S:Body/submitFormResponse').first
        form_submission_id = root.locate('formSubmissionId').first.text.to_i

        {
          success: true,
          formSubmissionId: form_submission_id,
          timestamp: root.locate('timeStamp').first&.text || Time.now.getlocal.to_s
        }
      rescue => e
        Rails.logger.error "#{form_id} form submission failed: #{e.message}"

        if e.is_a?(Ox::ParseError)
          PersonalInformationLog.create!(data: submission_body, error_class: 'Form1010Ezr FailedWithParsingError')
        end

        raise e
      end

      def submission_status(form_submission_id)
        response = perform(:post, '', status_body(form_submission_id))

        root = response.body.locate('S:Envelope/S:Body/retrieveFormSubmissionStatusResponse').first
        {
          status: root.locate('status').first&.text,
          messageType: root.locate('message/type').first&.text,
          messageDetail: root.locate('message/detail').first&.text,
          formSubmissionId: root.locate('formSubmissionId').first.text.to_i,
          timestamp: root.locate('timeStamp').first&.text || Time.now.getlocal.to_s
        }
      end

      # Savon *seems* like it should be setting these things correctly
      # from what the docs say. Our WSDL file is weird, maybe?
      SOAP_CLIENT = Savon.client(
        wsdl: HCA::Configuration::WSDL,
        env_namespace: :soap,
        element_form_default: :qualified,
        namespaces: {
          'xmlns:tns': 'http://va.gov/service/esr/voa/v1'
        },
        namespace: 'http://va.gov/schema/esr/voa/v1',
        log: false
      )

      def self.soap
        SOAP_CLIENT
      end

      private

      def log_payload_info(formatted_form, submission_body)
        form_name = formatted_form.dig('va:form', 'va:formIdentifier', 'va:value')
        attachments = formatted_form.dig('va:form', 'va:attachments')
        attachment_count = attachments&.length || 0
        # Log the attachment sizes in descending order
        if attachment_count.positive?
          # Convert the attachments into xml format so they resemble what will be sent to VES
          attachment_sizes =
            attachments.map { |a| a.to_xml.size }.sort.reverse!.map { |size| number_to_human_size(size) }.join(', ')

          Rails.logger.info("Attachment sizes in descending order: #{attachment_sizes}")
        end

        Rails.logger.info(
          "Payload for submitted #{form_name}: Body size of #{number_to_human_size(submission_body.bytesize)} " \
          "with #{attachment_count} attachment(s)"
        )
      end

      def submission_body(formatted_form)
        content = Gyoku.xml(formatted_form, unwrap: [:'va:attachments'])
        submission_body = self.class.soap.build_request(:save_submit_form, message: content).body
        log_payload_info(formatted_form, submission_body)

        submission_body
      end

      def status_body(form_submission_id)
        self.class.soap.build_request(
          :get_form_submission_status,
          message: { formSubmissionId: form_submission_id }
        ).body
      end
    end
  end
end
