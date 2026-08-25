# frozen_string_literal: true

module V1
  class FacilityAccountsController < ApplicationController
    service_tag 'debt-resolution'
    before_action :authorize_facility_account_history
    before_action :authorize_icn

    def index
      facility_accounts = service.facility_accounts(status: facility_accounts_params[:status])
      render json: MedicalCopays::FacilityAccounts::FacilityAccountSerializer.index(**facility_accounts), status: :ok
    end

    def show
      account = service.facility_account(params[:facility_id])
      raise Common::Exceptions::RecordNotFound, params[:facility_id] if account.nil?

      render json: MedicalCopays::FacilityAccounts::FacilityAccountSerializer.show(account)
    end

    private

    def facility_accounts_params
      params.permit(:status)
    end

    def authorize_icn
      raise Common::Exceptions::Forbidden, detail: 'User ICN is required' if current_user.icn.blank?
    end

    def authorize_facility_account_history
      raise Common::Exceptions::Forbidden unless facility_account_history_enabled?
    end

    def facility_account_history_enabled?
      MedicalCopays::FeatureFlagHelpers.facility_account_history_enabled?(current_user)
    end

    def service
      @service ||= MedicalCopays::FacilityAccounts::Service.new(current_user)
    end
  end
end
