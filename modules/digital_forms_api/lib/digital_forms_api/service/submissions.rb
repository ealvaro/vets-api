# frozen_string_literal: true

require 'digital_forms_api/service/base'

module DigitalFormsApi
  module Service
    # Submissions API
    class Submissions < Base
      # POST submit form structured data
      #
      # @see DigitalFormsApi::Validation#validate_submission_request
      #
      # @param payload [Hash] validated form data
      # @param metadata [Hash] fields in addition to the payload
      # @param dry_run [Boolean] perform a dry run in which no action is taken except validation by the endpoint
      def submit(payload, metadata, dry_run: false)
        request = validate_submission_request(payload, metadata)

        headers = {}

        # @see DigitalFormsApi::Service::Base#context
        tags = {
          form_id: metadata[:formId],
          ep_code: metadata[:epCode],
          claim_label: metadata[:claimLabel]
        }
        @context = tags.merge(tags:)

        perform :post, "submissions?dry-run=#{dry_run}", request, headers
      end

      # GET get a form submission
      def retrieve(submission_id)
        perform :get, "submissions/#{submission_id}", {}, {}
      end

      # GET get a form submission by document id
      # Retrieve details for a previously submitted form using the associated CE document ID
      def by_document_id(document_id)
        perform :get, "submissions/by-document-id/#{document_id}", {}, {}
      end

      private

      # @see DigitalFormsApi::Service::Base#endpoint
      def endpoint
        'submissions'
      end

      # end Submissions
    end

    # end Service
  end

  # end DigitalFormsApi
end
