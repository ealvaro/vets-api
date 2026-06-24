# frozen_string_literal: true

module SignIn
  module Constants
    module Auth
      ACCESS_TOKEN_COOKIE_NAME = 'vagov_access_token'
      ACCESS_DENIED = 'access_denied'
      ACR_VALUES = [LOA1 = 'loa1',
                    LOA3 = 'loa3',
                    IAL1 = 'ial1',
                    IAL2 = 'ial2',
                    IAL2_REQUIRED  = 'urn:acr.va.gov:verified-facial-match-required',
                    IAL2_PREFERRED = 'urn:acr.va.gov:verified-facial-match-preferred',
                    MIN = 'min'].freeze
      ACR_TRANSLATIONS = [IDME_LOA1 = 'http://idmanagement.gov/ns/assurance/loa/1/vets',
                          IDME_LOA3 = 'http://idmanagement.gov/ns/assurance/loa/3',
                          IDME_LOA3_FORCE = 'http://idmanagement.gov/ns/assurance/loa/3_force',
                          IDME_IAL1 = 'http://idmanagement.gov/ns/assurance/ial/1/aal/1',
                          IDME_IAL2 = 'http://idmanagement.gov/ns/assurance/ial/2/aal/2',
                          IDME_CLASSIC_LOA3 = 'classic_loa3',
                          IDME_MHV_LOA1 = 'myhealthevet',
                          IDME_MHV_LOA3 = 'myhealthevet_loa3',
                          IDME_COMPARISON_MINIMUM = 'comparison:minimum',
                          MHV_PREMIUM_VERIFIED = %w[Premium].freeze,
                          LOGIN_GOV_IAL0 = 'http://idmanagement.gov/ns/assurance/ial/0',
                          LOGIN_GOV_IAL1 = 'http://idmanagement.gov/ns/assurance/ial/1',
                          LOGIN_GOV_IAL2 = 'http://idmanagement.gov/ns/assurance/ial/2',
                          LOGIN_GOV_VERIFIED = 'urn:acr.login.gov:verified',
                          LOGIN_GOV_IAL2_REQUIRED = 'urn:acr.login.gov:verified-facial-match-required',
                          LOGIN_GOV_IAL2_PREFERRED = 'urn:acr.login.gov:verified-facial-match-preferred',
                          CLEAR_IAL1 = 'ial1',
                          CLEAR_IAL2 = 'ial2'].freeze
      ANTI_CSRF_COOKIE_NAME = 'vagov_anti_csrf_token'
      AUTHENTICATION_TYPES = [COOKIE = 'cookie', API = 'api', MOCK = 'mock'].freeze
      AUTHORIZE_ROUTE_PATH = '/v0/sign_in/authorize'
      AUTHORIZE_SSO_ROUTE_PATH = '/v0/sign_in/authorize_sso'
      BROKER_CODE = 'sis'
      CALLBACK_PATH = '/v0/sign_in/callback'
      CERTS_ROUTE_PATH = '/sign_in/openid_connect/certs'
      CLIENT_STATE_MINIMUM_LENGTH = 22
      CODE_CHALLENGE_METHOD = 'S256'
      CSP_TYPES = [IDME = 'idme', LOGINGOV = 'logingov', MHV = 'mhv', CLEAR = 'clear'].freeze
      OPERATION_TYPES = [SIGN_UP = 'sign_up',
                         AUTHORIZE = 'authorize',
                         AUTHORIZE_SSO = 'authorize_sso',
                         INTERSTITIAL_VERIFY = 'interstitial_verify',
                         INTERSTITIAL_SIGNUP = 'interstitial_signup',
                         VERIFY_CTA_AUTHENTICATED = 'verify_cta_authenticated',
                         VERIFY_PAGE_AUTHENTICATED = 'verify_page_authenticated',
                         VERIFY_PAGE_UNAUTHENTICATED = 'verify_page_unauthenticated'].freeze
      GRANT_TYPES = [AUTH_CODE_GRANT = 'authorization_code',
                     JWT_BEARER_GRANT = Urn::JWT_BEARER_GRANT_TYPE,
                     TOKEN_EXCHANGE_GRANT = Urn::TOKEN_EXCHANGE_GRANT_TYPE].freeze
      ENFORCED_TERMS = [VA_TERMS = 'VA'].freeze
      ASSERTION_ENCODE_ALGORITHM = 'RS256'
      IAL = [IAL_ONE = 1, IAL_TWO = 2].freeze
      INFO_COOKIE_NAME = 'vagov_info_token'
      JWT_ENCODE_ALGORITHM = 'RS256'
      LOA = [LOA_ONE = 1, LOA_THREE = 3].freeze
      LOGOUT_ROUTE_PATH = '/v0/sign_in/logout'
      REFRESH_ROUTE_PATH = '/v0/sign_in/refresh'
      REFRESH_TOKEN_COOKIE_NAME = 'vagov_refresh_token'
      RESPONSE_TYPES_SUPPORTED = ['code'].freeze
      REVIEW_INSTANCE_CALLBACK_PROXY_PATH = 'v0/sign_in/review_instance_callback_proxy'
      REVOKE_ROUTE_PATH = '/v0/sign_in/revoke'
      SERVICE_ACCOUNT_ACCESS_TOKEN_COOKIE_NAME = 'service_account_access_token'
      SCOPES = [DEVICE_SSO = 'device_sso'].freeze
      SUBJECT_TYPES_SUPPORTED = ['public'].freeze
      TOKEN_ENDPOINT_AUTH_METHODS = %w[private_key_jwt client_secret_basic none].freeze
      TOKEN_ROUTE_PATH = '/v0/sign_in/token'
      USERINFO_ROUTE_PATH = '/sign_in/user_info'
      REVIEW_INSTANCES_HOST = 'vfs.va.gov'
    end
  end
end
