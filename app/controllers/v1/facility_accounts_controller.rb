# frozen_string_literal: true

module V1
  class FacilityAccountsController < ApplicationController
    service_tag 'debt-resolution'
    before_action :authorize_facility_account_history
    before_action :authorize_icn

    def index
      render json: MedicalCopays::FacilityAccounts::FacilityAccountSerializer.index(**service.facility_accounts)
    end

    private

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
