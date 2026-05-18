# frozen_string_literal: true

module RuboCop
  module Cop
    # Detects when a non-Exception value is passed to the `exception:` key
    # in logger method calls. SemanticLogger expects an Exception object for
    # the `exception:` keyword; passing a String (e.g., `e.message`, `e.to_s`,
    # or string interpolation) causes silent logging failures where exception
    # metadata is lost.
    #
    # Flags both inline hash arguments and local variables assigned to a hash
    # literal in the same method scope before being passed to a logger call.
    # Does not flag standalone hashes that are never passed to a logger.
    #
    # @example
    #   # bad — inline hash
    #   Rails.logger.error('failed', exception: e.message)
    #   Rails.logger.error('failed', exception: e.class.to_s)
    #   Rails.logger.error('failed', exception: "#{e.class} - #{e.message}")
    #
    #   # bad — hash assigned to local variable then passed to logger
    #   details = { exception: e.class.to_s }
    #   Rails.logger.warn('msg', details)
    #
    #   # good
    #   Rails.logger.error('failed', exception: e)
    #
    class DangerousExceptionLogging < RuboCop::Cop::Base
      MSG = 'Pass the Exception object directly to `exception:` instead of a ' \
            'String. Use `exception: e` rather than `exception: e.message`, ' \
            '`exception: e.to_s`, or string interpolation. SemanticLogger ' \
            'extracts class, message, and backtrace automatically.'

      MSG_DSTR = 'Avoid embedding exception details (class, message, backtrace) in the ' \
                 'logger message string via interpolation. Pass the Exception object ' \
                 'using `exception: e` instead — SemanticLogger extracts these automatically.'

      LOG_METHODS = %i[debug info warn error fatal].freeze

      def on_send(node)
        return unless logger_call?(node)

        first_arg = node.arguments.first
        check_message_dstr(first_arg) if first_arg&.dstr_type?

        node.arguments.each do |arg|
          case arg.type
          when :hash
            check_hash_pairs(arg)
          when :lvar
            check_lvar_hash(arg, node)
          end
        end
      end

      private

      # Matches any receiver ending in `.logger` (e.g. Rails.logger, self.logger,
      # MyService.logger) — intentionally broad because SemanticLogger is mixed
      # into many classes via `include SemanticLogger::Loggable`, exposing a
      # `logger` instance method that behaves the same as Rails.logger.
      def logger_call?(node)
        LOG_METHODS.include?(node.method_name) &&
          node.receiver&.send_type? &&
          node.receiver.method_name == :logger
      end

      def check_hash_pairs(hash_node)
        hash_node.pairs.each do |pair|
          next unless exception_key?(pair)
          next unless dangerous_value?(pair.value)
          next if nested_in_context?(pair)

          add_offense(pair)
        end
      end

      # Tracks a local variable back to its hash-literal assignment and checks
      # the hash pairs for dangerous exception: values.
      #
      # What this catches:
      #   details = { exception: e.class.to_s }
      #   Rails.logger.warn('msg', details)
      #
      # What it can't catch:
      #   # method call
      #   details = build_details(e)
      #   Rails.logger.warn('msg', details)
      #
      #   # mutation after assignment
      #   details = {}
      #   details[:exception] = e.class.to_s
      #   Rails.logger.warn('msg', details)
      #
      #   # reassigned before use
      #   details = { exception: e.class.to_s }
      #   details = details.merge(other)
      #   Rails.logger.warn('msg', details)
      def check_lvar_hash(lvar_node, send_node)
        var_name = lvar_node.children.first
        assignment = find_lvasgn(send_node, var_name)
        return unless assignment

        assigned_value = assignment.children.last
        return unless assigned_value.is_a?(RuboCop::AST::Node) && assigned_value.hash_type?

        check_hash_pairs(assigned_value)
      end

      # Finds the most recent lvasgn for var_name within the enclosing method
      # scope, before the logger call. Handles simple `var = { ... }` assignments
      # only; does not follow mutation (merge, []=, etc.) or method calls.
      def find_lvasgn(node, var_name)
        scope = node.each_ancestor(:def, :defs, :block).first
        return unless scope

        scope.each_descendant(:lvasgn)
             .select { |n| n.children.first == var_name && n.loc.line < node.loc.line }
             .last
      end

      def exception_key?(node)
        key = node.key
        key.sym_type? && key.value == :exception
      end

      def dangerous_value?(value)
        string_coercion?(value) || value.dstr_type?
      end

      # Matches e.message, e.to_s, e.class.to_s, e.class.name, and similar
      # send chains that coerce an Exception to a String
      def string_coercion?(node)
        node.send_type? && %i[message to_s name inspect].include?(node.method_name)
      end

      def check_message_dstr(dstr_node)
        add_offense(dstr_node, message: MSG_DSTR) if exception_dstr_pattern?(dstr_node)
      end

      # True when a dstr interpolates .backtrace on any receiver, or both
      # .class and .message on the *same* receiver. Requiring the same receiver
      # avoids false positives like "#{job.class} failed: #{msg.message}" where
      # neither object is an exception.
      def exception_dstr_pattern?(dstr_node)
        interpolated_receivers_for(dstr_node, :backtrace).any? ||
          interpolated_receivers_for(dstr_node, :class)
            .intersect?(interpolated_receivers_for(dstr_node, :message))
      end

      # Returns the source strings of receivers for all sends of +method_name+
      # found inside string interpolations in the dstr.
      def interpolated_receivers_for(dstr_node, method_name)
        dstr_node.each_descendant(:begin).flat_map do |interp|
          interp.each_descendant(:send)
                .select { |s| s.method_name == method_name }
                .map { |s| s.receiver&.source }
        end.compact
      end

      # Check if this exception: pair is nested inside a context: hash
      def nested_in_context?(node)
        parent = node.parent
        return false unless parent&.hash_type?

        grandparent = parent.parent
        return false unless grandparent&.pair_type?

        gp_key = grandparent.key
        gp_key.sym_type? && gp_key.value == :context
      end
    end
  end
end
