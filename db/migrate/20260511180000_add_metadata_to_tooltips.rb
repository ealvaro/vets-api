# frozen_string_literal: true

class AddMetadataToTooltips < ActiveRecord::Migration[7.2]
  def change
    add_column :tooltips, :metadata, :jsonb, default: {}, null: false
  end
end
