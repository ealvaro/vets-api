# frozen_string_literal: true

require 'meb_api/v0/base_confirmation_email_worker'

module MebApi
  module V0
    class Submit225490FormConfirmation < BaseConfirmationEmailWorker
      FORM_TYPE = MebApi::ConfirmationEmailConfig::FORM_225490
      FORM_TAG = MebApi::ConfirmationEmailConfig::TAG_225490
    end
  end
end
