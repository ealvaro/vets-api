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
        @context = build_context(**tags)

        perform :post, "submissions?dry-run=#{dry_run}", request, headers
      end

      # GET get a form submission
      def retrieve(submission_id, form_id: nil)
        @context = submission_context(submission_id:, form_id:)
        perform :get, "submissions/#{submission_id}", {}, {}
      end

      # GET get a form submission by document id
      # Retrieve details for a previously submitted form using the associated CE document ID
      def by_document_id(document_id, form_id: nil)
        @context = submission_context(document_id:, form_id:)
        perform :get, "submissions/by-document-id/#{document_id}", {}, {}
      end

      private

      # Build a context hash for submission-related service requests
      #
      # @param submission_id [String, nil] the submission identifier
      # @param document_id [String, nil] the document identifier
      # @param form_id [String, nil] the form identifier
      # @return [Hash] context hash with compact tags for monitoring
      def submission_context(submission_id: nil, document_id: nil, form_id: nil)
        build_context(**{
          form_id:,
          submission_id:,
          document_id:
        }.compact)
      end

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
