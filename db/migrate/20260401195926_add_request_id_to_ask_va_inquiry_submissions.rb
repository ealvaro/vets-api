class AddRequestIdToAskVAInquirySubmissions < ActiveRecord::Migration[7.2]
  def change
    add_column :ask_va_inquiry_submissions, :request_id, :string, null: false
  end
end
