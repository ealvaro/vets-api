# frozen_string_literal: true

require 'forms/submission_statuses/report'

module V0
  module MyVA
    class SubmissionStatusesController < ApplicationController
      service_tag 'form-submission-statuses'

      def show
        report = Forms::SubmissionStatuses::Report.new(
          user_account: @current_user.user_account,
          allowed_forms: forms_based_on_feature_toggle,
          gateway_options: gateway_options_for_user
        )
        result = report.run
        response_status = status_from(result)

        log_partial_success(result) if response_status == 296
        StatsD.increment('api.forms.submission_statuses.response', tags: ["status:#{response_status}"])

        render json: serializable_from(result).to_json, status: response_status
      end

      private

      def restricted_list_of_forms
        forms = []
        # Always include benefits intake forms for backward compatibility
        forms += restricted_benefits_intake_forms
        forms += decision_reviews_forms_if_enabled
        forms += FormProfile::ALL_FORMS[:hca] if display_hca_forms?
        forms
      end

      def restricted_benefits_intake_forms
        FormProfile::RESTRICTED_FORMS + uploadable_forms
      end

      def decision_reviews_forms_if_enabled
        return [] unless display_decision_reviews_forms?

        # we use form0995_form4142 here to distinguish SC 4142s from standalone 4142s
        %w[
          20-0995
          20-0996
          10182
          form0995_form4142
        ]
      end

      def uploadable_forms
        FormProfile::ALL_FORMS[:form_upload]
      end

      def serializable_from(result)
        hash = SubmissionStatusSerializer.new(result.submission_statuses).serializable_hash
        hash[:errors] = result.errors
        hash
      end

      def status_from(result)
        result.errors.present? ? 296 : 200
      end

      def log_partial_success(result)
        failed_gateways = result.errors.filter_map { |e| e[:source] }.uniq
        Rails.logger.warn(
          'Submission statuses partial success (296)',
          failed_gateways:,
          total_errors: result.errors.size,
          total_submissions: result.submission_statuses.size
        )
      end

      def forms_based_on_feature_toggle
        return nil if display_all_forms?

        restricted_list_of_forms
      end

      def gateway_options_for_user
        options = {
          # ALWAYS enable benefits intake for backward compatibility
          # The feature flag only controls whether to show ALL forms vs restricted list
          benefits_intake_enabled: true,
          decision_reviews_enabled: display_decision_reviews_forms?,
          ivc_champva_enabled: display_ivc_champva_forms?,
          hca_status_card_enabled: display_hca_forms?
        }

        options[:user_email] = @current_user.email if options[:ivc_champva_enabled]
        options
      end

      def display_all_forms?
        # When this flag is true, show ALL forms without restriction (pass nil for allowed_forms)
        # When false, show the restricted list of forms
        Flipper.enabled?(
          :my_va_display_all_lighthouse_benefits_intake_forms,
          @current_user
        )
      end

      def display_decision_reviews_forms?
        Flipper.enabled?(
          :my_va_display_decision_reviews_forms,
          @current_user
        )
      end

      def display_ivc_champva_forms?
        Flipper.enabled?(
          :benefits_claims_ivc_champva_provider,
          @current_user
        )
      end

      def display_hca_forms?
        Flipper.enabled?(:hca_status_card_enabled, @current_user)
      end
    end
  end
end
