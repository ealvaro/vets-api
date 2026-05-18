# frozen_string_literal: true

MHVHealthRecordsPolicy = Struct.new(:user, :mhv_health_records) do
  def access?
    user.loa3? && user.mhv_user_account.present?
  end
end
