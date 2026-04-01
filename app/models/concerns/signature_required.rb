# frozen_string_literal: true

module SignatureRequired
  extend ActiveSupport::Concern

  SIGNATURE_ADMIN_REGEX = /[\s_]*(Privacy Issues?|Release of Information Medical Records|Record Amendment)[\s_]*Admin/i
  RELEASE_OF_INFO_REGEX = /[\s_]*Release[\s_]*of[\s_]*Information/i
  SIGNATURE_REQUIRED_REGEX = Regexp.union(SIGNATURE_ADMIN_REGEX, RELEASE_OF_INFO_REGEX)

  def signature_required
    return false if name.blank?

    SIGNATURE_REQUIRED_REGEX.match?(name)
  end
end
