# frozen_string_literal: true

module MyHealth
  module FacilityLoggingConcern
    extend ActiveSupport::Concern

    private

    ##
    # Appends the user's associated VA treatment facility IDs and Cerner (Oracle Health) facility IDs
    # to the Rails instrumentation payload for every MHV controller action. This enables per-facility
    # monitoring across all MHV health apps (medical records, secure messaging, prescriptions, etc.).
    #
    def append_info_to_payload(payload)
      super

      return unless current_user
      return unless Flipper.enabled?(:mhv_facility_logging, current_user)

      facility_ids = current_user.va_treatment_facility_ids || []
      cerner_ids = current_user.cerner_facility_ids || []

      payload[:facility_ids] = facility_ids if facility_ids.present?
      payload[:cerner_facility_ids] = cerner_ids if cerner_ids.present?
    rescue => e
      Rails.logger.warn("FacilityLoggingConcern: failed to append facility info: #{e.message}")
    end
  end
end
