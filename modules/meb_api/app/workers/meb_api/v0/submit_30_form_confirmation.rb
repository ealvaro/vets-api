# frozen_string_literal: true

require 'meb_api/v0/base_confirmation_email_worker'

module MebApi
  module V0
    class Submit30FormConfirmation < BaseConfirmationEmailWorker
      FORM_TYPE = MebApi::ConfirmationEmailConfig::FORM_1990_CHAPTER30
      FORM_TAG = MebApi::ConfirmationEmailConfig::TAG_1990_CHAPTER30
    end
  end
end
