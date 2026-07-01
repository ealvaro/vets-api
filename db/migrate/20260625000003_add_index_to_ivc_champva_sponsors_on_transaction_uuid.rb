# frozen_string_literal: true

class AddIndexToIvcChampvaSponsorsOnTransactionUuid < ActiveRecord::Migration[7.2]
  disable_ddl_transaction!

  def change
    add_index :ivc_champva_sponsors,
              :transaction_uuid,
              unique: true,
              algorithm: :concurrently,
              if_not_exists: true
  end
end
