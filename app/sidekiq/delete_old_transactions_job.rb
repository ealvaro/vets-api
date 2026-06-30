# frozen_string_literal: true

class DeleteOldTransactionsJob
  include Sidekiq::Job

  # :nocov:
  def perform
    AsyncTransaction::Base
      .stale
      .find_each do |tx|
        tx.destroy!
    rescue ActiveRecord::RecordNotDestroyed => e
      Rails.logger.error(
        'DeleteOldTransactionsJob raised an exception',
        model: self.class.to_s, transaction_id: tx.id, exception: e
      )
      end
  end
  # :nocov:
end
