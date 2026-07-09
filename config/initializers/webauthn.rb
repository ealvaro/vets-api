# frozen_string_literal: true

if IdentitySettings.webauthn.enabled
  WebAuthn.configure do |config|
    config.rp_id           = IdentitySettings.webauthn.rp_id
    config.rp_name         = IdentitySettings.webauthn.rp_name
    config.allowed_origins = IdentitySettings.webauthn.web_origins
  end
end
