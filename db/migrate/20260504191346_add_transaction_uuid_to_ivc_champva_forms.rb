class AddTransactionUuidToIvcChampvaForms < ActiveRecord::Migration[7.2]
  def change
    add_column :ivc_champva_forms, :transaction_uuid, :uuid
  end
end
