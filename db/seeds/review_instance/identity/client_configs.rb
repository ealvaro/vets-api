# frozen_string_literal: true

vaweb = SignIn::ClientConfig.find_or_initialize_by(client_id: 'vaweb')
vaweb.update!(authentication: SignIn::Constants::Auth::COOKIE,
              anti_csrf: true,
              redirect_uri: "https://#{Settings.review_instance_slug}.#{SignIn::Constants::Auth::REVIEW_INSTANCES_HOST}/auth/login/callback",
              access_token_duration: SignIn::Constants::AccessToken::VALIDITY_LENGTH_SHORT_MINUTES,
              access_token_audience: 'va.gov',
              pkce: true,
              auth_method: 'pkce',
              logout_redirect_uri: "https://#{Settings.review_instance_slug}.#{SignIn::Constants::Auth::REVIEW_INSTANCES_HOST}",
              enforced_terms: SignIn::Constants::Auth::VA_TERMS,
              terms_of_use_url: "https://#{Settings.review_instance_slug}.#{SignIn::Constants::Auth::REVIEW_INSTANCES_HOST}/terms-of-use",
              shared_sessions: true,
              refresh_token_duration: SignIn::Constants::RefreshToken::VALIDITY_LENGTH_SHORT_MINUTES,
              service_levels: SignIn::Constants::Auth::ACR_VALUES)

arp = SignIn::ClientConfig.find_or_initialize_by(client_id: 'arp')
arp.update!(authentication: SignIn::Constants::Auth::COOKIE,
            anti_csrf: true,
            pkce: true,
            auth_method: 'pkce',
            description: 'Accredited Representative Portal',
            redirect_uri: "https://#{Settings.review_instance_slug}.#{SignIn::Constants::Auth::REVIEW_INSTANCES_HOST}/representative/auth/login/callback",
            access_token_duration: SignIn::Constants::AccessToken::VALIDITY_LENGTH_SHORT_MINUTES,
            access_token_attributes: %w[first_name last_name email all_emails],
            refresh_token_duration: SignIn::Constants::RefreshToken::VALIDITY_LENGTH_SHORT_MINUTES,
            logout_redirect_uri: "https://#{Settings.review_instance_slug}.#{SignIn::Constants::Auth::REVIEW_INSTANCES_HOST}/representative",
            credential_service_providers: [SignIn::Constants::Auth::IDME, SignIn::Constants::Auth::LOGINGOV],
            service_levels: [SignIn::Constants::Auth::LOA3, SignIn::Constants::Auth::IAL2])

vamock = SignIn::ClientConfig.find_or_initialize_by(client_id: 'vamock')
vamock.update!(authentication: SignIn::Constants::Auth::MOCK,
               anti_csrf: true,
               pkce: true,
               auth_method: 'pkce',
               redirect_uri: "https://#{Settings.review_instance_slug}.#{SignIn::Constants::Auth::REVIEW_INSTANCES_HOST}/auth/login/callback",
               access_token_duration: SignIn::Constants::AccessToken::VALIDITY_LENGTH_SHORT_MINUTES,
               access_token_audience: 'va.gov',
               logout_redirect_uri: "https://#{Settings.review_instance_slug}.#{SignIn::Constants::Auth::REVIEW_INSTANCES_HOST}",
               shared_sessions: true,
               refresh_token_duration: SignIn::Constants::RefreshToken::VALIDITY_LENGTH_SHORT_MINUTES)
