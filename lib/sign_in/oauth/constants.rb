# frozen_string_literal: true

module SignIn
  module OAuth
    module Constants
      IDME = 'idme'
      MHV = 'mhv'

      AUTHORIZE = 'authorize'
      SIGN_UP = 'sign_up'

      IAL_ONE = 1
      IAL_TWO = 2
      LOA_ONE = 1
      LOA_THREE = 3

      IDME_LOA1 = 'http://idmanagement.gov/ns/assurance/loa/1/vets'
      IDME_LOA3 = 'http://idmanagement.gov/ns/assurance/loa/3'
      IDME_LOA3_FORCE = 'http://idmanagement.gov/ns/assurance/loa/3_force'
      IDME_IAL1 = 'http://idmanagement.gov/ns/assurance/ial/1/aal/1'
      IDME_IAL2 = 'http://idmanagement.gov/ns/assurance/ial/2/aal/2'
      IDME_MHV_LOA1 = 'myhealthevet'
      IDME_MHV_LOA3 = 'myhealthevet_loa3'
      IDME_COMPARISON_MINIMUM = 'comparison:minimum'

      LOGIN_GOV_IAL1 = 'http://idmanagement.gov/ns/assurance/ial/1'
      LOGIN_GOV_IAL2 = 'http://idmanagement.gov/ns/assurance/ial/2'

      CLEAR_IAL2 = 'ial2'

      REVIEW_INSTANCE_CALLBACK_PROXY_PATH = 'v0/sign_in/review_instance_callback_proxy'
    end
  end
end
