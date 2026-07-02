# frozen_string_literal: true

class AddClearUuidToAuditUserIdentifierTypeEnum < ActiveRecord::Migration[7.2]
  def up
    add_enum_value :audit_user_identifier_types, 'clear_uuid'
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
