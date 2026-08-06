# frozen_string_literal: true

module SubmissionTracking
  extend ActiveSupport::Concern

  private

  def submission_fields(current_user)
    {
      form_uuid: metadata&.dig('uuid'),
      identity: data['certifier_role'],
      current_user_loa: current_user&.loa&.[](:current) || 0,
      current_user_ial: derive_ial(current_user),
      email_used: metadata&.dig('primaryContactInfo', 'email') ? 'yes' : 'no'
    }
  end

  def derive_ial(user)
    return 0 unless user&.user_verification

    user.user_verification.verified? ? SignIn::Constants::Auth::IAL_TWO : SignIn::Constants::Auth::IAL_ONE
  end
end
