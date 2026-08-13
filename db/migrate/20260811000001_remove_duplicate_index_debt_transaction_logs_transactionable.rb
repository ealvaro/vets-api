# frozen_string_literal: true

class RemoveDuplicateIndexDebtTransactionLogsTransactionable < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def up
    # idx_on_transactionable_type_transactionable_id_52a8eee11c covers the same columns in the same order;
    # this older index is a true duplicate.
    remove_index :debt_transaction_logs,
                 name: 'index_debt_transaction_logs_on_transactionable',
                 algorithm: :concurrently,
                 if_exists: true
  end

  def down
    add_index :debt_transaction_logs,
              %i[transactionable_type transactionable_id],
              name: 'index_debt_transaction_logs_on_transactionable',
              algorithm: :concurrently
  end
end
