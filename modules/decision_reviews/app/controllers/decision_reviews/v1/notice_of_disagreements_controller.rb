# frozen_string_literal: true

require 'decision_reviews/v1/helpers'
module DecisionReviews
  module V1
    class NoticeOfDisagreementsController < AppealsBaseController
      include DecisionReviews::V1::Helpers
      service_tag 'board-appeal'

      def show
        render json: decision_review_service.get_notice_of_disagreement(params[:id]).body
      rescue => e
        log_exception_to_personal_information_log(
          e, error_class: error_class(method: 'show', exception_class: e.class), id: params[:id]
        )
        raise
      end

      def create
        req_body_obj = normalize_area_code_for_lighthouse_schema(request_body_hash)
        update2026 = nod_form_update2026?(req_body_obj)
        nod_response_body = AppealSubmission.submit_nod(
          current_user: @current_user,
          request_body_hash: req_body_obj,
          decision_review_service:
        )

        log_appeal_record_created(nod_response_body, update2026)

        render json: nod_response_body
      rescue => e
        ::Rails.logger.error(
          message: "Exception occurred while submitting Notice Of Disagreement: #{e.message}",
          backtrace: e.backtrace
        )
        handle_personal_info_error(e)
      end

      private

      # The 2026 form update (decision_review_nod_form_update_2026) removes the
      # VHA-appeal question and adds the "request a decision as soon as
      # possible" docket-switch waiver. The frontend submit transformer always
      # includes the `requestDecisionAsap` key (even when false) for updated
      # submissions and never for legacy ones, so key presence identifies the
      # updated flow without an explicit payload flag.
      def nod_form_update2026?(req_body_obj)
        req_body_obj.dig('data', 'attributes')&.key?('requestDecisionAsap') || false
      end

      def log_appeal_record_created(nod_response_body, update2026)
        submitted_appeal_uuid = nod_response_body.dig('data', 'id')
        appeal_submission_id = AppealSubmission.find_by(submitted_appeal_uuid:)&.id
        ::Rails.logger.info(
          message: 'Notice of Disagreement Appeal Record Created',
          form_id: '10182',
          update2026:,
          appeal_submission_id:,
          lighthouse_submission: {
            id: submitted_appeal_uuid
          }
        )
      rescue => e
        ::Rails.logger.error(
          message: 'Failed to log Notice of Disagreement record creation',
          error_class: e.class.name
        )
      end

      def error_class(method:, exception_class:)
        "#{self.class.name}##{method} exception #{exception_class} (NOD_V1)"
      end

      def handle_personal_info_error(e)
        request = begin
          { body: request_body_hash }
        rescue
          request_body_debug_data
        end

        log_exception_to_personal_information_log(
          e, error_class: error_class(method: 'create', exception_class: e.class), request:
        )
        raise
      end
    end
  end
end
