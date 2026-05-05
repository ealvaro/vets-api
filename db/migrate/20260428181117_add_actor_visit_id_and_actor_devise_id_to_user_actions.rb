# frozen_string_literal: true

class AddActorVisitIdAndActorDeviseIdToUserActions < ActiveRecord::Migration[7.2]
  def change
    add_column :user_actions, :acting_visit_id, :string, null: true
    add_column :user_actions, :acting_device_id, :string, null: true
  end
end
