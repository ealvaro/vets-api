# frozen_string_literal: true

module SignIn
  class SessionRecord < ApplicationRecord
    self.table_name = 'sign_in_session_records'

    belongs_to :user_account, dependent: nil

    validate :confirm_client_id
    validates :handle, presence: true, uniqueness: true

    has_kms_key
    has_encrypted :sign_in_ip, key: :kms_key, **lockbox_options
    has_encrypted :user_agent, key: :kms_key, **lockbox_options
    has_encrypted :location, key: :kms_key, **lockbox_options

    def self.sign_out(handles)
      now = Time.zone.now
      # rubocop:disable Rails/SkipsModelValidations
      where(handle: handles, signed_out_at: nil).update_all(signed_out_at: now, updated_at: now)
      # rubocop:enable Rails/SkipsModelValidations
    end

    private

    def confirm_client_id
      errors.add(:base, 'Client id must map to a configuration') unless ClientConfig.valid_client_id?(client_id:)
    end
  end
end
