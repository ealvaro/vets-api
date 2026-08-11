# frozen_string_literal: true

module MedicalCopays
  # Centralized definitions of the feature-flag checks used across the
  # medical copays / facility account (Payment History) code paths.
  #
  # Each method takes an explicit `user` argument so this module can be
  # consumed by both controllers (passing `current_user`) and plain
  # service objects (passing their own user reference).
  module FeatureFlagHelpers
    module_function

    def facility_account_history_enabled?(user)
      Flipper.enabled?(:enable_facility_account_history, user)
    end

    def lighthouse_copays_enabled?(user)
      Flipper.enabled?(:enable_lighthouse_copays, user)
    end

    def show_payment_history_enabled?(user)
      Flipper.enabled?(:vha_show_payment_history, user)
    end
  end
end
