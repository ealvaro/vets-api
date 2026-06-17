# frozen_string_literal: true

ClaimsEvidencePolicy = Struct.new(:user, :claims_evidence) do
  def access?
    user.present? && user.loa3? && user.icn.present?
  end
end
