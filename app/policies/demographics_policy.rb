# frozen_string_literal: true

DemographicsPolicy = Struct.new(:user, :gender_identity) do
  def access?
    user&.icn.present?
  end

  def access_update?
    user&.icn.present?
  end
end
