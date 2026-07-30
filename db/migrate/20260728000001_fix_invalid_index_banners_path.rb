# frozen_string_literal: true

class FixInvalidIndexBannersPath < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def up
    remove_index :banners, name: 'index_banners_on_path', algorithm: :concurrently, if_exists: true
    add_index :banners, :path,
              name: 'index_banners_on_path',
              algorithm: :concurrently
  end

  def down
    remove_index :banners, name: 'index_banners_on_path', algorithm: :concurrently, if_exists: true
  end
end
