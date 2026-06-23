# frozen_string_literal: true

require 'decision_reviews/v1/service'
require_relative '../dataset'
require_relative '../error_handler'
require_relative 'base_gateway'

module Forms
  module SubmissionStatuses
    module Gateways
      class Hca1010EzGateway < BaseGateway
        NORMALIZED_STATUSES = {
          enrolled: :vbms,
          pending_mt: :in_progress,
          pending_other: :in_progress,
          pending_purpleheart: :in_progress,
          pending_unverified: :in_progress
        }.freeze

        def submissions
          # this must return a #present? value for submissions? in BaseGateway#data to be true
          [@user_account]
        end

        def api_statuses(submissions)
          submitted_current_user = submissions.first
          record = HealthCareApplication.enrollment_status(submitted_current_user.icn, true)
          status = NORMALIZED_STATUSES[record[:parsed_status]]

          return [nil, nil] unless status

          api_status_result = {
            id: submitted_current_user.id,
            status:,
            created_at: record[:application_date],
            updated_at: record[:effective_date]
          }

          [[api_status_result], nil]
        rescue => e
          status = e.respond_to?(:status_code) ? e.status_code : 500
          errors = error_handler.handle_error(status:, body: { message: e.message })
          [nil, errors]
        end
      end
    end
  end
end
