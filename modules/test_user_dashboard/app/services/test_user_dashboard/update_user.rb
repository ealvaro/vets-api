# frozen_string_literal: true

require 'vets/shared_logging'

module TestUserDashboard
  class UpdateUser
    include Vets::SharedLogging

    attr_accessor :tud_account, :user

    def initialize(user)
      @tud_account = TudAccount.find_by(user_account_id: user.user_account_uuid)
    end

    def call(time = nil)
      return unless tud_account

      checkout_time = { checkout_time: time }
      valid_update = tud_account.update(checkout_time)
      Rails.logger.warn('[TestUserDashboard] UpdateUser invalid update', checkout_time) unless valid_update
    end
  end
end
