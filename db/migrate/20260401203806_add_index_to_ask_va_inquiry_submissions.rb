class AddIndexToAskVAInquirySubmissions < ActiveRecord::Migration[7.2]
  disable_ddl_transaction!

  def change
    add_index :ask_va_inquiry_submissions, :request_id, unique: true, algorithm: :concurrently, if_not_exists: true
  end
end
