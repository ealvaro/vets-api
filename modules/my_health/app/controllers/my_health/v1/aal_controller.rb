# frozen_string_literal: true

require 'mhv/aal/client'
require 'mhv/aal/activity_page'

module MyHealth
  module V1
    class AALController < ApplicationController
      include MyHealth::AALClientConcerns
      service_tag 'mhv-aal'

      before_action :verify_feature_enabled, only: :index
      before_action :authorize_aal
      before_action :authenticate_aal_client!

      # GET /my_health/v1/aal
      # Returns paginated account activity log entries for the current user.
      def index
        response = aal_client.get_activities(activity_params)
        page = AAL::ActivityPage.new(response.body)

        render json: MyHealth::V1::ActivitySerializer.new(page.activities).serializable_hash.merge(
          meta: { pagination: page.pagination }
        )
      end

      # POST /my_health/v1/aal
      # Records an account activity log entry for the current user.
      def create
        once_per_session = ActiveModel::Type::Boolean.new.cast(params[:once_per_session])

        create_aal!(aal_params, once_per_session:)
        head :no_content
      end

      protected

      # Override AALClientConcerns#product: the read path (index) always uses the dedicated AAL
      # product/credentials, while the write path (create) selects the product from request params.
      def product
        action_name == 'index' ? :aal : super
      end

      def aal_params
        params.require(:aal).permit(
          :activity_type,
          :action,
          :completion_time,
          :performer_type,
          :detail_value,
          :status
        )
      end

      def activity_params
        params.permit(:from_date, :to_date, :page, :limit, :sort, :select, :style)
      end

      def authorize_aal
        if current_user&.mhv_correlation_id.blank?
          raise Common::Exceptions::Forbidden,
                detail: 'You do not have access to the AAL service'
        end
      end

      def verify_feature_enabled
        unless Flipper.enabled?(:mhv_account_activity_log_enabled, current_user)
          raise Common::Exceptions::Forbidden,
                detail: 'Account activity log feature is not enabled'
        end
      end
    end
  end
end
