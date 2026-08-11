# frozen_string_literal: true

module V1
  class FacilityAccountsController < ApplicationController
    service_tag 'debt-resolution'
    before_action :authorize_facility_account_history

    private

    def authorize_facility_account_history
      raise Common::Exceptions::Forbidden unless facility_account_history_enabled?
    end

    def facility_account_history_enabled?
      MedicalCopays::FeatureFlagHelpers.facility_account_history_enabled?(current_user)
    end

    def use_lighthouse?
      MedicalCopays::FeatureFlagHelpers.lighthouse_copays_enabled?(current_user)
    end
  end
end
