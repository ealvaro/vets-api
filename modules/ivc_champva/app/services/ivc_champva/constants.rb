# frozen_string_literal: true

module IvcChampva
  module Constants
    # Must match the frontend's BACKEND_INCORRECT_PASSWORD_MSG exactly (strict === check).
    # See vets-website: src/platform/forms-system/src/js/actions.js
    INCORRECT_PASSWORD_DETAIL = 'The password you entered is incorrect. Please try again.'
  end
end
