# frozen_string_literal: true

module RepresentationManagement
  module V0
    class PowerOfAttorneyRequestsController < RepresentationManagement::V0::PowerOfAttorneyRequestBaseController
      service_tag 'representation-management'
      before_action :feature_enabled
      after_action :increment_statsd_metric, only: :create, if: -> { response.successful? }

      STATSD_KEY_PREFIX = 'api.representation_management.power_of_attorney_requests'

      def create
        if !form.valid?
          render json: { errors: form.errors.full_messages }, status: :unprocessable_entity
        elsif orchestrate_response[:errors]&.any?
          render json: { errors: orchestrate_response[:errors] }, status: :unprocessable_entity
        else
          log_dependent_state
          render json: RepresentationManagement::PowerOfAttorneyRequestSerializer.new(orchestrate_response[:request]),
                 status: :created
        end
      end

      private

      def feature_enabled
        routing_error unless Flipper.enabled?(:appoint_a_representative_enable_v2_features)
      end

      def form_params
        params.require(:power_of_attorney_request).permit(params_permitted)
      end

      def flatten_form_params
        @flatten_form_params ||=
          {
            representative_id: form_params[:representative][:id],
            organization_id: form_params[:representative][:organization_id],
            record_consent: [true, 'true'].include?(form_params[:record_consent]),
            consent_limits:,
            consent_address_change: [true, 'true'].include?(form_params[:consent_address_change])
          }.merge(flatten_veteran_params(form_params))
          .merge(flatten_claimant_params(form_params))
      end

      def dependent
        form_params[:claimant].present?
      end

      def service_branch
        form_params.dig(:veteran, :service_branch)
      end

      def consent_limits
        if form_params[:consent_limits].all?(&:blank?)
          []
        else
          form_params[:consent_limits]
        end
      end

      def form
        @form ||= RepresentationManagement::Form2122DigitalSubmission.new(user: current_user, dependent:,
                                                                          **flatten_form_params)
      end

      def orchestrate_response
        @orchestrate_response ||=
          RepresentationManagement::PowerOfAttorneyRequestService::Orchestrate.new(
            data: flatten_form_params.merge(consent_limits: form.normalized_limitations_of_consent),
            dependent:,
            service_branch:,
            user: current_user
          ).call
      end

      def log_dependent_state
        if form.dependent
          AccreditedRepresentativePortal::DependentLookupService
            .new(veteran: { first_name: form.veteran_first_name,
                            last_name: form.veteran_last_name,
                            ssn: form.veteran_social_security_number,
                            birth_date: form.veteran_date_of_birth })
            .log_dependent_relationship_state(dependent: {
                                                first_name: form.claimant_first_name,
                                                last_name: form.claimant_last_name,
                                                icn: form.user.icn,
                                                birth_date: form.claimant_date_of_birth
                                              })
        end
      rescue => e
        Rails.logger.warn(
          '[RepresentationManagement::V0::PowerOfAttorneyRequestsController] Dependent state logging failed', e
        )
      end

      def increment_statsd_metric
        StatsD.increment("#{STATSD_KEY_PREFIX}.#{action_name}.success",
                         tags: ["claimant_type:#{form.dependent.present? ? 'non_veteran' : 'veteran'}"])
      end
    end
  end
end
