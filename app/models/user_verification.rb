# frozen_string_literal: true

class UserVerification < ApplicationRecord
  has_one :deprecated_user_account, dependent: :destroy, required: false
  belongs_to :user_account, dependent: nil
  has_one :user_credential_email, dependent: :destroy, required: false
  belongs_to :webauthn_credential, class_name: 'SignIn::WebauthnCredential', dependent: :destroy, optional: true

  validate :single_credential_identifier
  validate :backing_uuid_credentials

  scope :idme, -> { where.not(idme_uuid: nil) }
  scope :logingov, -> { where.not(logingov_uuid: nil) }
  scope :mhv, -> { where.not(mhv_uuid: nil) }
  scope :clear, -> { where.not(clear_uuid: nil) }
  scope :entra, -> { where.not(entra_uuid: nil) }

  def self.find_by_type!(type, identifier)
    user_verification =
      case type
      when SignIn::Constants::Auth::LOGINGOV
        find_by(logingov_uuid: identifier)
      when SignIn::Constants::Auth::IDME
        find_by(idme_uuid: identifier)
      when SignIn::Constants::Auth::MHV
        find_by(mhv_uuid: identifier)
      when SignIn::Constants::Auth::CLEAR
        find_by(clear_uuid: identifier)
      when SignIn::Constants::Auth::ENTRA
        find_by(entra_uuid: identifier)
      end
    raise ActiveRecord::RecordNotFound unless user_verification

    user_verification
  end

  def self.find_by_type(type, identifier)
    find_by_type!(type, identifier)
  rescue ActiveRecord::RecordNotFound
    nil
  end

  def lock!
    update!(locked: true)
  end

  def unlock!
    update!(locked: false)
  end

  def verified?
    verified_at.present? && user_account.verified?
  end

  def credential_type
    return SignIn::Constants::Auth::IDME if idme_uuid
    return SignIn::Constants::Auth::LOGINGOV if logingov_uuid
    return SignIn::Constants::Auth::CLEAR if clear_uuid
    return SignIn::Constants::Auth::ENTRA if entra_uuid

    SignIn::Constants::Auth::MHV if mhv_uuid
  end

  def credential_identifier
    idme_uuid || logingov_uuid || clear_uuid || entra_uuid || mhv_uuid
  end

  def backing_credential_identifier
    logingov_uuid || idme_uuid || clear_uuid || entra_uuid || backing_idme_uuid
  end

  private

  # One, and only one, of these can be defined
  # If two or more are defined, or if none are defined, then a validation error is raised
  def single_credential_identifier
    unless [idme_uuid, logingov_uuid, clear_uuid, entra_uuid, mhv_uuid,
            webauthn_credential_id].count(&:present?) == 1
      errors.add(:base, 'Must specify one, and only one, credential identifier')
    end
  end

  # All credentials require either an idme_uuid, logingov_uuid, or clear_uuid credential types
  # store the backing idme_uuid as backing_idme_uuid
  def backing_uuid_credentials
    unless idme_uuid || logingov_uuid || clear_uuid || entra_uuid || backing_idme_uuid || webauthn_credential_id
      errors.add(:base, 'Must define either an idme_uuid, logingov_uuid, clear_uuid, entra_uuid, or backing_idme_uuid')
    end
  end
end
