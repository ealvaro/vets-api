# frozen_string_literal: true

module AccreditedRepresentativePortal
  module V0
    class RepresentativeInProgressFormsController < ApplicationController
      skip_after_action :verify_pundit_authorization
      before_action :feature_enabled
      before_action :require_veteran_icn

      def show
        form = find_or_build_form
        render json: form&.data_and_metadata || {}
      end

      def update
        form = find_form || build_form
        form.update!(
          form_data: params[:formData],
          metadata: params[:metadata],
          expires_at: form.next_expires_at
        )
        render json: RepresentativeInProgressFormSerializer.new(form)
      end

      def destroy
        form = find_form or
          raise Common::Exceptions::RecordNotFound, params[:id]
        form.destroy

        head :no_content
      end

      private

      def feature_enabled
        routing_error unless Flipper.enabled?(:accredited_representative_portal_submit_686c_v2)
      end

      def require_veteran_icn
        return if veteran_icn.present?

        render json: { errors: [{ detail: 'claimant_id is required' }] },
               status: :unprocessable_entity
      end

      # Used by show/destroy — looks up by the full composite key.
      def find_form
        RepresentativeInProgressForm.for_rep_and_veteran(
          params[:id],
          @current_user.user_account_uuid,
          veteran_icn
        )
      end

      def find_or_build_form
        RepresentativeInProgressForm.build_for_rep_and_veteran(
          params[:id],
          @current_user.user_account_uuid,
          veteran_icn
        )
      end

      def build_form
        RepresentativeInProgressForm.new(
          form_id: params[:id],
          rep_user_account_id: @current_user.user_account_uuid,
          veteran_icn:
        )
      end

      def veteran_icn
        return @veteran_icn if defined?(@veteran_icn)

        # claimant_id is an IcnTemporaryIdentifier UUID
        @veteran_icn = IcnTemporaryIdentifier.lookup_icn(params[:claimant_id]) if params[:claimant_id].present?
      rescue ActiveRecord::RecordNotFound
        @veteran_icn = nil
      end
    end
  end
end
