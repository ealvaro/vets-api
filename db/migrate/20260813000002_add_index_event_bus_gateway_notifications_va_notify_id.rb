# frozen_string_literal: true

class AddIndexEventBusGatewayNotificationsVANotifyId < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def up
    add_index :event_bus_gateway_notifications,
              :va_notify_id,
              name: 'index_event_bus_gateway_notifications_on_va_notify_id',
              algorithm: :concurrently
  end

  def down
    remove_index :event_bus_gateway_notifications,
                 name: 'index_event_bus_gateway_notifications_on_va_notify_id',
                 algorithm: :concurrently
  end
end
