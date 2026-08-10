# frozen_string_literal: true

require 'caseflow/service'
require 'decision_reviews/v1/service'
require 'decision_reviews/v1/appealable_issues/service'
require 'decision_reviews/util/response_comparison'

module DecisionReviews
  module V1
    class AppealsBaseController < ApplicationController
      include FailedRequestLoggable
      before_action { authorize :appeals, :access? }

      APPEALABLE_ISSUES_COMPARISON_STATSD_KEY = 'api.decision_reviews.appealable_issues_comparison'
      APPEALABLE_ISSUES_COMPARISON_MESSAGE = 'Appealable issues comparison'

      # `type` differs between the two APIs by design: both OpenAPI specs pin it to a single-value
      # enum, "contestableIssue" for the existing API and "appealableIssue" for the new one, so a
      # comparison that respected it could never match. Keep this at exactly one entry -- every key
      # added is a difference the comparison stops noticing, and the comparison decides which
      # response the Veteran receives.
      APPEALABLE_ISSUES_IGNORED_KEYS = %w[type].freeze

      private

      def decision_review_service
        DecisionReviews::V1::Service.new
      end

      def appealable_issues_service
        DecisionReviews::V1::AppealableIssues::Service.new
      end

      def request_body_hash
        @request_body_hash ||= get_hash_from_request_body
      end

      def get_hash_from_request_body
        # rubocop:disable Style/ClassEqualityComparison
        # testing string b/c NullIO class doesn't always exist
        raise request_body_is_not_a_hash_error if request.body.class.name == 'Puma::NullIO'
        # rubocop:enable Style/ClassEqualityComparison

        body = JSON.parse request.body.string
        raise request_body_is_not_a_hash_error unless body.is_a?(Hash)

        body
      rescue JSON::ParserError
        raise request_body_is_not_a_hash_error
      end

      def request_body_is_not_a_hash_error
        DecisionReviews::V1::ServiceException.new key: 'DR_REQUEST_BODY_IS_NOT_A_HASH'
      end

      def request_body_debug_data
        {
          request_body_class_name: request.try(:body).class.name,
          request_body_string: request.try(:body).try(:string)
        }
      end

      def use_new_appealable_issues_service?
        Flipper.enabled?(:decision_review_use_new_appealable_issues_service, @current_user)
      end

      ##
      # Fetches contestable issues from the existing Decision Reviews API and, when the new
      # Appealable Issues API is enabled, fetches them from that API as well and logs whether the
      # two agree. See https://va.ghe.com/software/va.gov-team/issues/151026.
      #
      # The new service call and the comparison are both best effort: any failure in either is
      # logged and swallowed, so a broken comparison always falls back to the `decision_review`
      # response.
      #
      # When the two agree, the new service's response is the one rendered. "Agree" means the same
      # issues with the same attribute values, disregarding the `type` label and the order they
      # arrive in. So the rendered response can differ from what the `decision_review` path would
      # have returned in exactly two ways: the `type` string, which consumers pass through to the
      # submit endpoints whose schemas accept both values; and the sequence, which vets-website
      # re-sorts by decision date before display.
      #
      # @param form_id [String] "996" (HLR), "10182" (NOD), or "995" (SC)
      # @param decision_review [Proc] fetches issues from the existing Decision Reviews API
      # @param appealable_issues [Proc] fetches issues from the new Appealable Issues API
      # @return [Faraday::Response]
      #
      def appealable_issues_with_comparison(form_id:, decision_review:, appealable_issues:)
        decision_review_response = decision_review.call
        return decision_review_response unless use_new_appealable_issues_service?

        begin
          appealable_issues_response = appealable_issues.call
          comparison = DecisionReviews::Util::ResponseComparison.new(
            expected: decision_review_response.body,
            actual: appealable_issues_response.body,
            ignored_keys: APPEALABLE_ISSUES_IGNORED_KEYS,
            ignore_order: true
          )
          log_appealable_issues_comparison(form_id:, comparison:)
          comparison.equivalent? ? appealable_issues_response : decision_review_response
        rescue => e
          log_appealable_issues_comparison_error(form_id:, error: e)
          decision_review_response
        end
      end

      # `result` and the render gate are the same predicate, so `result:match` in Datadog is exactly
      # the set of requests served from the new API. A literal body comparison would be useless
      # here -- the differing `type` enums pin it to false for any Veteran with an issue -- so
      # `match` means "the same issues, disregarding the `type` label and their order".
      #
      # No user identifier is logged, deliberately. Per the VA platform PII guidelines
      # (https://depo-platform-documentation.scrollhelp.site/developer-docs/personal-identifiable-information-pii-guidelines)
      # a user UUID is PII, and nothing here needs tracing back to a Veteran: the question this
      # answers is "what share of requests agree, per form type", which the StatsD tags and these
      # counts already answer in aggregate.
      def log_appealable_issues_comparison(form_id:, comparison:)
        result = comparison.equivalent? ? 'match' : 'mismatch'
        StatsD.increment(APPEALABLE_ISSUES_COMPARISON_STATSD_KEY,
                         tags: ["form_id:#{form_id}", "result:#{result}"])
        payload = {
          message: APPEALABLE_ISSUES_COMPARISON_MESSAGE,
          form_id:,
          result:,
          # The comparison utility is domain-agnostic; name its counts for this pairing.
          comparison: {
            decision_review_issue_count: comparison.expected_count,
            appealable_issues_issue_count: comparison.actual_count,
            differing_attribute_names: comparison.differing_keys,
            ordering_differs: comparison.ordering_differs?
          }
        }
        Rails.logger.info(payload)
      end

      # Only the error class is logged. The new service already logs its own error detail, and an
      # exception raised while comparing could carry response body content, which is PII/PHI.
      def log_appealable_issues_comparison_error(form_id:, error:)
        StatsD.increment(APPEALABLE_ISSUES_COMPARISON_STATSD_KEY,
                         tags: ["form_id:#{form_id}", 'result:error'])
        payload = {
          message: "#{APPEALABLE_ISSUES_COMPARISON_MESSAGE} failed",
          form_id:,
          result: 'error',
          error_class: error.class.name
        }
        Rails.logger.error(payload)
      end
    end
  end
end
