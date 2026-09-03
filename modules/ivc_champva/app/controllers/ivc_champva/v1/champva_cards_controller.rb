# frozen_string_literal: true

module IvcChampva
  module V1
    class ChampvaCardsController < ApplicationController
      skip_after_action :set_csrf_header

      NOT_ENROLLED_MESSAGE = 'We could not find a CHAMPVA enrollment for this account.'
      INELIGIBLE_MESSAGE = 'This account is not currently eligible for a CHAMPVA benefits card.'
      UPSTREAM_MESSAGE = 'We could not retrieve your CHAMPVA card details. Please try again later.'
      MISSING_ICN_MESSAGE = 'Your account is missing the information needed to look up CHAMPVA enrollment.'
      NOT_VERIFIED_MESSAGE = 'You must verify your identity before you can view your CHAMPVA card.'

      MESSAGES = {
        'not_enrolled' => NOT_ENROLLED_MESSAGE,
        'ineligible' => INELIGIBLE_MESSAGE,
        'upstream_timeout' => UPSTREAM_MESSAGE,
        'upstream_error' => UPSTREAM_MESSAGE,
        'missing_icn' => MISSING_ICN_MESSAGE,
        'not_verified' => NOT_VERIFIED_MESSAGE
      }.freeze

      def get_benefits_card
        return render_feature_disabled unless Flipper.enabled?(:champva_benefits_card, current_user)
        # MPIData#profile returns nil below LOA3, so an unverified user has no ICN, name, or
        # date of birth to look up or render. Checked before the ICN so they get this rather
        # than the missing_icn error, which reads as an account data problem.
        return render_card_error('not_verified', :forbidden) unless current_user.loa3?
        return render_card_error('missing_icn', :unprocessable_content) if current_user.icn.blank?

        render_card_result(IvcChampva::ChampvaEligibilityService.benefits_card_for(current_user))
      end

      private

      def render_card_result(result)
        case result[:status]
        when :ok
          monitor.track_get_benefits_card
          render json: { data: { type: 'champva_card', attributes: result[:attributes] } }, status: :ok
        when :not_enrolled
          render_card_error('not_enrolled', :not_found)
        when :ineligible
          render_ineligible(result)
        when :upstream_timeout
          render_card_error('upstream_timeout', :gateway_timeout, context: { error_class: result[:error_class] })
        else
          render_card_error('upstream_error', :bad_gateway, context: { error_class: result[:error_class] })
        end
      end

      # A beneficiary VES knows about but will not issue a card to. The frontend renders static
      # content for this and needs no card data, so the service's attributes are withheld.
      #
      # Deliberately its own code rather than reusing not_enrolled: the two are different
      # situations (a record that does not qualify vs. no record at all), and whether
      # ineligibility should stay a 404 is still open. Moving it to a 200 means rendering
      # result[:attributes] here; nothing else has to change.
      #
      # The metric is tagged with the specific verdict rather than the shared code, so Datadog can
      # separate expiries from denials without the frontend having to care.
      def render_ineligible(result)
        enrollment_status = result[:enrollment_status]
        render_card_error('ineligible', :not_found, reason: enrollment_status, body: { enrollment_status: })
      end

      # The one place a card error is both rendered and counted, so a new rejection reason cannot
      # be added without also getting a metric.
      #
      # @param code [String] error code returned to the caller, and its key into MESSAGES
      # @param status [Symbol] Rails status symbol
      # @param reason [String] Datadog tag value; defaults to the error code
      # @param body [Hash] extra fields to merge into the rendered error object
      # @param context [Hash] extra PII-free fields for the log, not the response
      def render_card_error(code, status, reason: code, body: {}, context: {})
        monitor.track_benefits_card_error(reason, Rack::Utils.status_code(status), context.compact)
        render json: { error: { code:, message: MESSAGES.fetch(code) }.merge(body) }, status:
      end

      # Predates the card work and keeps its own body shape, which is the module's convention for a
      # disabled feature rather than this endpoint's error envelope. Counted anyway so rollout
      # traffic against a disabled flag is visible; the reason tag keeps it out of the way of the
      # real rejections.
      def render_feature_disabled
        monitor.track_benefits_card_error('feature_disabled', 404)
        render json: { error_message: 'Not found' }, status: :not_found
      end

      def monitor
        @monitor ||= IvcChampva::Monitor.new
      end
    end
  end
end
