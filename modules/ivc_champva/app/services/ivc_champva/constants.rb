# frozen_string_literal: true

module IvcChampva
  module Constants
    # Must match the frontend's BACKEND_INCORRECT_PASSWORD_MSG exactly (strict === check).
    # See vets-website: src/platform/forms-system/src/js/actions.js
    INCORRECT_PASSWORD_DETAIL = 'The password you entered is incorrect. Please try again.'

    OHI_ATTACHMENT_IDS = ['VA form 10-7959c', 'vha_10_7959c'].freeze
  end
end
