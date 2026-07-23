# frozen_string_literal: true

module AccreditedRepresentativePortal
  module V0
    class InProgressFormsController < ApplicationController
      skip_after_action :verify_pundit_authorization
      before_action :feature_enabled

      FORM_21A_ID = '21a'

      def show
        form = find_form
        render json: form&.data_and_metadata || {}
      end

      def update
        existing_form = find_form
        return persist_and_render(existing_form) if existing_form.present?

        # New-draft creation path.
        new_form = build_form
        return persist_and_render(new_form) unless pilot_enforced?(new_form)

        admit_and_persist(new_form)
      end

      def destroy
        form = find_form or
          raise Common::Exceptions::RecordNotFound, params[:id]
        form.destroy

        head :no_content
      end

      private

      # Whether the pilot gate should authorize this brand-new draft. Only Form 21a drafts,
      # and only while the pilot flag is on; otherwise drafts are created as before.
      def pilot_enforced?(form)
        form.form_id == FORM_21A_ID &&
          Flipper.enabled?(:accredited_representative_portal_form_21a_pilot, @current_user)
      end

      # Call 2 of the pilot gate. The admission create and the in-progress-form save share one
      # transaction so a slot is never consumed without its draft (and vice versa); the advisory
      # lock inside admit! is held until this transaction commits, keeping the monthly cap exact.
      def admit_and_persist(form)
        ActiveRecord::Base.transaction do
          if Form21aPilotGate.admit!(@current_user) == :open
            persist_and_render(form)
          else
            render_pilot_closed
            raise ActiveRecord::Rollback
          end
        end
      end

      def persist_and_render(form)
        form.update!(
          form_data: params[:formData],
          metadata: params[:metadata],
          expires_at: form.next_expires_at
        )

        render json: InProgressFormSerializer.new(form)
      end

      def render_pilot_closed
        render json: { errors: ['Form 21a pilot is at capacity for this month'] }, status: :forbidden
      end

      # Checks if the feature flag accredited_representative_portal_form_21a is enabled or not
      def feature_enabled
        routing_error unless Flipper.enabled?(:accredited_representative_portal_form_21a)
      end

      def find_form
        InProgressForm.form_for_user(params[:id], @current_user)
      end

      def build_form
        build_form_for_user(params[:id], @current_user)
      end

      # NOTE: The in-progress form module can upstream this convenience that
      # allows the caller to not know about details like legacy foreign key
      # relations. It is totally analogous to the query convenience
      # `form_for_user` that they expose.
      def build_form_for_user(form_id, user)
        InProgressForm.new.tap do |form|
          form.real_user_uuid = user.uuid
          form.assign_attributes(
            user_uuid: user.uuid,
            user_account: user.user_account,
            form_id:
          )
        end
      end
    end
  end
end
