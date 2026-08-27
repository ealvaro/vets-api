# frozen_string_literal: true

module SignIn
  class WebauthnCredential < ApplicationRecord
    self.table_name = 'sign_in_webauthn_credentials'

    has_one :user_verification, dependent: :nullify, required: false

    validates :credential_id, presence: true, uniqueness: true
    validates :public_key, :sign_count, presence: true
    validates :backup_eligible, :backed_up, inclusion: { in: [true, false] }

    scope :active, -> { where(revoked_at: nil) }

    def revoke!
      update!(revoked_at: Time.zone.now)
    end
  end
end
