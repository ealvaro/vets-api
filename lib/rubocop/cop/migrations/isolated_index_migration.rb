# frozen_string_literal: true

module RuboCop
  module Cop
    module Migrations
      # Enforces that index operations (add_index, remove_index) are isolated
      # in their own migration files, separate from other schema changes, and
      # that each migration contains at most one index operation.
      #
      # Mixing index operations with column or table changes makes it hard to
      # recover safely if the migration fails partway through, especially when
      # concurrent index builds are involved.
      #
      # @example
      #   # bad - index mixed with column change
      #   def change
      #     add_column :users, :name, :string
      #     add_index :users, :name, algorithm: :concurrently
      #   end
      #
      #   # bad - multiple indexes in one migration
      #   def change
      #     add_index :users, :email, algorithm: :concurrently
      #     add_index :users, :name, algorithm: :concurrently
      #   end
      #
      #   # good - isolated index migration
      #   def change
      #     add_index :users, :email, algorithm: :concurrently
      #   end
      #
      #   # good - schema changes only, no indexes
      #   def change
      #     add_column :users, :name, :string
      #     add_column :users, :email, :string
      #   end
      class IsolatedIndexMigration < RuboCop::Cop::Base
        MSG_MIXED = 'Index operations (`add_index`, `remove_index`) must be in ' \
                    'their own migration, separate from other schema changes. ' \
                    'Split this migration into separate files.'

        MSG_MULTIPLE = 'Only one index operation is allowed per migration. ' \
                       'Split multiple index operations into separate migration files.'

        CREATE_INDEX_SQL_PATTERN = /\bCREATE\s+(?:UNIQUE\s+)?INDEX
                 (?:\s+CONCURRENTLY)?
                 (?:\s+IF\s+NOT\s+EXISTS)?
                 \s+([^\s]+)
                 \s+ON\s+([^\s(]+)/imx

        INDEX_METHODS = %i[add_index remove_index].freeze

        NON_INDEX_SCHEMA_METHODS = %i[
          add_column remove_column rename_column change_column
          change_column_null change_column_default
          create_table drop_table rename_table
          add_timestamps remove_timestamps
          add_reference add_belongs_to remove_reference remove_belongs_to
          add_foreign_key remove_foreign_key
          add_check_constraint remove_check_constraint
          add_exclusion_constraint remove_exclusion_constraint
          add_unique_constraint remove_unique_constraint
          change_table
        ].freeze

        def on_new_investigation
          return unless migration_file?

          migration_defs = migration_method_nodes
          return if migration_defs.empty?

          index_calls = migration_defs.flat_map { |node| index_calls_of(node) }
          return if index_calls.empty?

          other_calls = migration_defs.flat_map { |node| bare_calls_of(node, NON_INDEX_SCHEMA_METHODS) }
          non_index_execute_calls = migration_defs.flat_map { |node| non_index_execute_calls_of(node) }

          if other_calls.any? || non_index_execute_calls.any?
            index_calls.each { |n| add_offense(n.loc.selector, message: MSG_MIXED) }
          elsif index_calls.size > 1
            return unless multiple_index_targets?(index_calls)

            index_calls.drop(1).each { |n| add_offense(n.loc.selector, message: MSG_MULTIPLE) }
          end
        end

        private

        def migration_file?
          processed_source.file_path.match?(%r{db/migrate/})
        end

        def migration_method?(node)
          %i[change up down].include?(node.method_name)
        end

        def migration_method_nodes
          ast = processed_source.ast
          return [] unless ast

          ast.each_descendant(:def).select { |node| migration_method?(node) }
        end

        # Returns send nodes with no explicit receiver (bare method calls) that
        # match any of the given method names, anywhere in the subtree.
        def bare_calls_of(node, method_names)
          node.each_node(:send).select do |n|
            n.receiver.nil? && method_names.include?(n.method_name)
          end
        end

        def index_calls_of(node)
          bare_calls_of(node, INDEX_METHODS) + index_execute_calls_of(node)
        end

        def index_execute_calls_of(node)
          node.each_node(:send).select do |n|
            n.receiver.nil? && n.method_name == :execute && execute_index_operation?(n)
          end
        end

        def non_index_execute_calls_of(node)
          node.each_node(:send).select do |n|
            n.receiver.nil? && n.method_name == :execute && !execute_index_operation?(n)
          end
        end

        def multiple_index_targets?(index_calls)
          index_calls.map { |n| index_target_key(n) }.uniq.size > 1
        end

        def index_target_key(node)
          table = normalize_table_identifier(node.arguments.first&.source)
          name = normalize_sql_identifier(index_option_source(node, :name))
          column = node.arguments[1]&.source || index_option_source(node, :column)

          if node.method_name == :execute
            table, name = execute_index_target(node)
            column = nil
          end

          return [nil, name] if name

          target = normalized_column_identifier(column) || node.source
          [table, target]
        end

        def execute_index_operation?(node)
          sql = execute_sql(node)
          return false unless sql

          sql.match?(/\bCREATE\s+(?:UNIQUE\s+)?INDEX\b/i) ||
            sql.match?(/\bDROP\s+INDEX\b/i)
        end

        def execute_index_target(node)
          sql = execute_sql(node)
          return [nil, nil] unless sql

          create_match = sql.match(CREATE_INDEX_SQL_PATTERN)
          if create_match
            table = normalize_sql_identifier(create_match[2])
            name = normalize_sql_identifier(create_match[1])
            return [table, name]
          end

          drop_match = sql.match(/\bDROP\s+INDEX(?:\s+CONCURRENTLY)?(?:\s+IF\s+EXISTS)?\s+([^\s;]+)/im)
          return [nil, normalize_sql_identifier(drop_match[1])] if drop_match

          [nil, sql.gsub(/\s+/, ' ').strip]
        end

        def execute_sql(node)
          arg = node.arguments.first
          return unless arg

          return arg.value if arg.str_type?

          arg.source if arg.dstr_type?
        end

        def normalize_sql_identifier(identifier)
          return nil unless identifier

          identifier.delete('"').split('.').last
        end

        def normalize_table_identifier(identifier)
          normalize_sql_identifier(identifier)
        end

        def normalized_column_identifier(column)
          return nil unless column

          column.to_s.gsub(/\s+/, ' ').strip
        end

        def index_option_source(node, key)
          hash_arg = node.arguments.find(&:hash_type?)
          return nil unless hash_arg

          pair = hash_arg.pairs.find { |p| p.key.sym_type? && p.key.value == key }
          pair&.value&.source
        end
      end
    end
  end
end
