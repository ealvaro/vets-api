# frozen_string_literal: true

require 'support/rubocop_spec_helper'

RSpec.describe RuboCop::Cop::Migrations::IsolatedIndexMigration, :config do
  let(:migration_path) { 'db/migrate/20240101000000_example.rb' }
  let(:module_migration_path) { 'modules/foo/db/migrate/20240101000000_example.rb' }
  let(:non_migration_path) { 'app/models/user.rb' }

  # ── offenses ──────────────────────────────────────────────────────────────

  context 'when add_index is mixed with add_column' do
    it 'registers an offense on the index method name' do
      expect_offense(<<~RUBY, migration_path)
        class AddIndexToUsers < ActiveRecord::Migration[7.0]
          def change
            add_column :users, :email, :string
            add_index :users, :email, algorithm: :concurrently
            ^^^^^^^^^ #{described_class::MSG_MIXED}
          end
        end
      RUBY
    end
  end

  context 'when remove_index is mixed with remove_column' do
    it 'registers an offense on the index method name' do
      expect_offense(<<~RUBY, migration_path)
        class RemoveIndexFromUsers < ActiveRecord::Migration[7.0]
          def change
            remove_column :users, :email
            remove_index :users, :email
            ^^^^^^^^^^^^ #{described_class::MSG_MIXED}
          end
        end
      RUBY
    end
  end

  context 'when add_index is mixed with create_table' do
    it 'registers an offense on the index method name' do
      expect_offense(<<~RUBY, migration_path)
        class CreateUsersAndIndex < ActiveRecord::Migration[7.0]
          def change
            create_table :users do |t|
              t.string :name
            end
            add_index :users, :name
            ^^^^^^^^^ #{described_class::MSG_MIXED}
          end
        end
      RUBY
    end
  end

  context 'when add_index is mixed with add_reference' do
    it 'registers an offense on the index method name' do
      expect_offense(<<~RUBY, migration_path)
        class AddRefAndIndex < ActiveRecord::Migration[7.0]
          def change
            add_reference :orders, :user, null: false
            add_index :orders, :user_id, algorithm: :concurrently
            ^^^^^^^^^ #{described_class::MSG_MIXED}
          end
        end
      RUBY
    end
  end

  context 'when execute CREATE INDEX is mixed with schema changes' do
    it 'registers an offense on execute' do
      expect_offense(<<~RUBY, migration_path)
        class MixedExecuteCreateIndex < ActiveRecord::Migration[7.0]
          def change
            add_column :users, :email, :string
            execute 'CREATE INDEX index_users_on_email ON users (email)'
            ^^^^^^^ #{described_class::MSG_MIXED}
          end
        end
      RUBY
    end
  end

  context 'when execute DROP INDEX is mixed with schema changes' do
    it 'registers an offense on execute' do
      expect_offense(<<~RUBY, migration_path)
        class MixedExecuteDropIndex < ActiveRecord::Migration[7.0]
          def change
            add_column :users, :email, :string
            execute 'DROP INDEX index_users_on_email'
            ^^^^^^^ #{described_class::MSG_MIXED}
          end
        end
      RUBY
    end
  end

  context 'when migration has multiple add_index calls and no other schema changes' do
    it 'registers an offense on the second index method name' do
      expect_offense(<<~RUBY, migration_path)
        class AddTwoIndexesToUsers < ActiveRecord::Migration[7.0]
          disable_ddl_transaction!

          def change
            add_index :users, :email, algorithm: :concurrently
            add_index :users, :name, algorithm: :concurrently
            ^^^^^^^^^ #{described_class::MSG_MULTIPLE}
          end
        end
      RUBY
    end
  end

  context 'when migration has three index calls' do
    it 'registers offenses on the second and third index method names' do
      expect_offense(<<~RUBY, migration_path)
        class AddThreeIndexes < ActiveRecord::Migration[7.0]
          disable_ddl_transaction!

          def change
            add_index :users, :email, algorithm: :concurrently
            add_index :users, :name, algorithm: :concurrently
            ^^^^^^^^^ #{described_class::MSG_MULTIPLE}
            add_index :users, :phone, algorithm: :concurrently
            ^^^^^^^^^ #{described_class::MSG_MULTIPLE}
          end
        end
      RUBY
    end
  end

  context 'when migration has multiple execute CREATE INDEX calls for different targets' do
    it 'registers an offense on the second execute' do
      expect_offense(<<~RUBY, migration_path)
        class MultipleExecuteCreateIndexes < ActiveRecord::Migration[7.0]
          disable_ddl_transaction!

          def change
            execute 'CREATE INDEX index_users_on_email ON users (email)'
            execute 'CREATE INDEX index_users_on_name ON users (name)'
            ^^^^^^^ #{described_class::MSG_MULTIPLE}
          end
        end
      RUBY
    end
  end

  context 'when migration has multiple execute DROP INDEX calls for different targets' do
    it 'registers an offense on the second execute' do
      expect_offense(<<~RUBY, migration_path)
        class MultipleExecuteDropIndexes < ActiveRecord::Migration[7.0]
          disable_ddl_transaction!

          def change
            execute 'DROP INDEX index_users_on_email'
            execute 'DROP INDEX index_users_on_name'
            ^^^^^^^ #{described_class::MSG_MULTIPLE}
          end
        end
      RUBY
    end
  end

  context 'when mixing is in an up method' do
    it 'registers an offense in up' do
      expect_offense(<<~RUBY, migration_path)
        class MixedUpMigration < ActiveRecord::Migration[7.0]
          def up
            add_column :users, :email, :string
            add_index :users, :email
            ^^^^^^^^^ #{described_class::MSG_MIXED}
          end
        end
      RUBY
    end
  end

  context 'when mixing is in a down method' do
    it 'registers an offense in down' do
      expect_offense(<<~RUBY, migration_path)
        class MixedDownMigration < ActiveRecord::Migration[7.0]
          def down
            remove_index :users, :email
            ^^^^^^^^^^^^ #{described_class::MSG_MIXED}
            remove_column :users, :email
          end
        end
      RUBY
    end
  end

  context 'when the file is in a module db/migrate path' do
    it 'registers an offense' do
      expect_offense(<<~RUBY, module_migration_path)
        class AddIndexToUsers < ActiveRecord::Migration[7.0]
          def change
            add_column :users, :email, :string
            add_index :users, :email
            ^^^^^^^^^ #{described_class::MSG_MIXED}
          end
        end
      RUBY
    end
  end

  context 'when schema changes and index operations are split across methods in one file' do
    it 'registers offenses for file-level mixing' do
      expect_offense(<<~RUBY, migration_path)
        class SplitAcrossMethods < ActiveRecord::Migration[7.0]
          def change
            add_column :users, :email, :string
          end

          def down
            remove_index :users, :email
            ^^^^^^^^^^^^ #{described_class::MSG_MIXED}
          end
        end
      RUBY
    end
  end

  context 'when index operations are split across up and down methods with matching columns' do
    it 'does not register an offense' do
      expect_no_offenses(<<~RUBY, migration_path)
        class SplitIndexOpsAcrossMethods < ActiveRecord::Migration[7.0]
          def up
            add_index :users, :email, algorithm: :concurrently
          end

          def down
            remove_index :users, :email
          end
        end
      RUBY
    end
  end

  context 'when up/down are a reversible pair for the same index' do
    it 'does not register an offense' do
      expect_no_offenses(<<~RUBY, migration_path)
        class ReversibleIndexPair < ActiveRecord::Migration[7.0]
          disable_ddl_transaction!

          def up
            add_index :users, :email, name: 'index_users_on_email', algorithm: :concurrently
          end

          def down
            remove_index :users, name: 'index_users_on_email', if_exists: true
          end
        end
      RUBY
    end
  end

  context 'when up/down index targets do not match' do
    it 'registers an offense for multiple index operations in one file' do
      expect_offense(<<~RUBY, migration_path)
        class NonMatchingIndexPair < ActiveRecord::Migration[7.0]
          disable_ddl_transaction!

          def up
            add_index :users, :email, algorithm: :concurrently
          end

          def down
            remove_index :users, :name
            ^^^^^^^^^^^^ #{described_class::MSG_MULTIPLE}
          end
        end
      RUBY
    end
  end

  context 'when a migration replaces a single index target' do
    it 'does not register an offense' do
      expect_no_offenses(<<~RUBY, migration_path)
        class ReplaceIndexTarget < ActiveRecord::Migration[7.0]
          disable_ddl_transaction!

          def up
            remove_index :banners, name: 'index_banners_on_path', if_exists: true
            add_index :banners, :path, name: 'index_banners_on_path', algorithm: :concurrently
          end

          def down
            remove_index :banners, name: 'index_banners_on_path', if_exists: true
          end
        end
      RUBY
    end
  end

  context 'when execute create/drop operations target the same index name across up/down' do
    it 'does not register an offense' do
      expect_no_offenses(<<~RUBY, migration_path)
        class RealisticExecuteIndexPair < ActiveRecord::Migration[7.1]
          disable_ddl_transaction!

          def up
            safety_assured do
              execute 'CREATE INDEX CONCURRENTLY index_veteran_representatives_on_lower_email ON veteran_representatives (LOWER(email))'
            end
          end

          def down
            safety_assured do
              execute 'DROP INDEX CONCURRENTLY index_veteran_representatives_on_lower_email'
            end
          end
        end
      RUBY
    end
  end

  context 'when execute create/drop index pairs are mixed with schema changes in one file' do
    it 'registers offenses for mixed schema and index operations' do
      expect_offense(<<~RUBY, migration_path)
        class RealisticMixedSchemaAndExecuteIndexes < ActiveRecord::Migration[7.2]
          disable_ddl_transaction!

          def up
            add_column :ivc_champva_forms, :new_col, :string
            execute 'CREATE INDEX CONCURRENTLY IF NOT EXISTS index_ivc_champva_forms_on_pending_form_uuid ON ivc_champva_forms (form_uuid)'
            ^^^^^^^ #{described_class::MSG_MIXED}
            execute 'CREATE INDEX CONCURRENTLY IF NOT EXISTS index_ivc_champva_forms_on_updated_at ON ivc_champva_forms (updated_at)'
            ^^^^^^^ #{described_class::MSG_MIXED}
          end

          def down
            execute 'DROP INDEX CONCURRENTLY IF EXISTS index_ivc_champva_forms_on_pending_form_uuid'
            ^^^^^^^ #{described_class::MSG_MIXED}
            execute 'DROP INDEX CONCURRENTLY IF EXISTS index_ivc_champva_forms_on_updated_at'
            ^^^^^^^ #{described_class::MSG_MIXED}
          end
        end
      RUBY
    end
  end

  # ── no offenses ───────────────────────────────────────────────────────────

  context 'when the migration only adds an index' do
    it 'does not register an offense' do
      expect_no_offenses(<<~RUBY, migration_path)
        class AddIndexToUsers < ActiveRecord::Migration[7.0]
          disable_ddl_transaction!

          def change
            add_index :users, :email, algorithm: :concurrently
          end
        end
      RUBY
    end
  end

  context 'when the migration only removes an index' do
    it 'does not register an offense' do
      expect_no_offenses(<<~RUBY, migration_path)
        class RemoveIndexFromUsers < ActiveRecord::Migration[7.0]
          disable_ddl_transaction!

          def change
            remove_index :users, :email
          end
        end
      RUBY
    end
  end

  context 'when the migration only adds columns' do
    it 'does not register an offense' do
      expect_no_offenses(<<~RUBY, migration_path)
        class AddColumnsToUsers < ActiveRecord::Migration[7.0]
          def change
            add_column :users, :name, :string
            add_column :users, :email, :string
          end
        end
      RUBY
    end
  end

  context 'when a new table is created with inline t.index inside the block' do
    it 'does not register an offense' do
      expect_no_offenses(<<~RUBY, migration_path)
        class CreateUsers < ActiveRecord::Migration[7.0]
          def change
            create_table :users do |t|
              t.string :name
              t.string :email
              t.index :email
              t.timestamps
            end
          end
        end
      RUBY
    end
  end

  context 'when the file is not a migration' do
    it 'does not register an offense for mixed index/schema calls in non-migration files' do
      expect_no_offenses(<<~RUBY, non_migration_path)
        class UserService
          def migrate_data
            add_column :users, :email, :string
            add_index :users, :email
          end
        end
      RUBY
    end
  end
end
