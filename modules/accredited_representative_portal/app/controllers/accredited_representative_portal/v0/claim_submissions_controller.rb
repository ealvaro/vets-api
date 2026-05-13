# frozen_string_literal: true

module AccreditedRepresentativePortal
  module V0
    class ClaimSubmissionsController < ApplicationController
      class NotFound < StandardError; end

      ATTEMPT_METRIC = 'ar.submissions.index.attempt'
      SUCCESS_METRIC = 'ar.submissions.index.success'
      ERROR_METRIC   = 'ar.submissions.index.error'

      def index
        monitoring = ar_monitoring
        monitoring.track_count(ATTEMPT_METRIC, tags: default_tags)

        authorize nil, policy_class: SavedClaimClaimantRepresentativePolicy
        serializer = SavedClaimClaimantRepresentativeSerializer.new(claim_submissions)
        render json: ({
          data: serializer.serializable_hash, meta: pagination_meta(claim_submissions)
        })
        monitoring.track_count(SUCCESS_METRIC, tags: default_tags)
      rescue ActiveRecord::RecordNotFound, NotFound
        monitoring&.track_count(ERROR_METRIC, tags: default_tags + ['reason:not_found'])
        render json: { error: 'Claimant id not found.' }, status: :not_found
      rescue => e
        normalized_reason = e.class.name.split('::').last
        monitoring.track_count(ERROR_METRIC, tags: default_tags + ["reason:#{normalized_reason}"])
        raise
      end

      private

      def pagination_meta(submissions)
        {
          page: {
            number: submissions.current_page,
            size: submissions.limit_value,
            total: submissions.total_entries,
            totalPages: submissions.total_pages
          }
        }
      end

      def validated_params
        @validated_params ||= params_schema.validate_and_normalize!(params.to_unsafe_h)
      end

      def params_schema
        SubmissionsService::ParamsSchema
      end

      def sort_params
        validated_params.fetch(:sort, {})
      end

      def page
        validated_params.dig(:page, :number)
      end

      def per_page
        validated_params.dig(:page, :size)
      end

      def claim_submissions
        policy_scope(SavedClaimClaimantRepresentative)
          .where(accredited_individual_registration_number: current_user.registration_numbers)
          .preload(scope_includes)
          .then { |it| sort_params.present? ? it.sorted_by(sort_params[:by], sort_params[:order]) : it }
          .paginate(page:, per_page:)
      end

      def scope_includes
        [{ saved_claim: [
          { form_submissions: :form_submission_attempts },
          %i[form_attachment persistent_attachments]
        ] }]
      end

      def ar_monitoring
        AccreditedRepresentativePortal::Monitoring.new(
          AccreditedRepresentativePortal::Monitoring::NAME,
          default_tags:
        )
      end

      def default_tags
        ["claimant_filter:#{params[:id].present?}"]
      end
    end
  end
end
