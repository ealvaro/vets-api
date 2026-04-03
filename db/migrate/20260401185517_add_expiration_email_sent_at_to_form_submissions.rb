# frozen_string_literal: true

class AddExpirationEmailSentAtToFormSubmissions < ActiveRecord::Migration[7.1]
  def change
    add_column :form_submissions, :expiration_email_sent_at, :datetime
  end
end
