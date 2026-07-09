# frozen_string_literal: true

class UserAccount < ApplicationRecord
  has_many :form_submissions, dependent: :nullify
  has_many :user_verifications, dependent: :destroy
  has_many :terms_of_use_agreements, dependent: :destroy
  has_many :tooltips, dependent: :destroy
  has_one :user_acceptable_verified_credential, dependent: :destroy
  has_one :veteran_onboarding, primary_key: :id, foreign_key: :user_account_uuid, inverse_of: :user_account,
                               dependent: :destroy
  has_many :webauthn_credentials, through: :user_verifications, source: :webauthn_credential

  validates :icn, uniqueness: true, allow_nil: true

  def verified?
    icn.present?
  end

  def needs_accepted_terms_of_use?
    verified? && !accepted_current_terms_of_use?
  end

  def lock!
    update!(locked: true)
  end

  def unlock!
    update!(locked: false)
  end

  private

  def accepted_current_terms_of_use?
    terms_of_use_agreements.current.last&.accepted?
  end
end
