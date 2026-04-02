# frozen_string_literal: true

require_relative 'attr_package_helpers'

module RuboCop
  module Cop
    class AttrPackageDeleteOnSuccess < RuboCop::Cop::Base
      include AttrPackageHelpers

      MSG_ENSURE = 'Do not delete Sidekiq::AttrPackage in an ensure block. ' \
                   "Delete on success and in sidekiq_retries_exhausted. See #{DOC_URL}.".freeze

      MSG_MISSING_IN_PERFORM = 'Jobs using Sidekiq::AttrPackage must call ' \
                               "Sidekiq::AttrPackage.delete on the success path in perform. See #{DOC_URL}.".freeze

      def on_ensure(node)
        ensure_body = node.children.last
        return unless ensure_body

        ensure_body.each_node(:send) do |send_node|
          next unless send_node.method?(:delete)
          next unless attr_package_receiver?(send_node.receiver)

          add_offense(send_node, message: MSG_ENSURE)
        end
      end

      def on_class(node)
        return unless sidekiq_job_class?(node)
        return unless uses_attr_package?(node)

        perform_node = find_perform_method(node)
        return unless perform_node
        return if deletes_attr_package_in_method_or_callees?(perform_node, node)

        add_offense(perform_node.loc.name, message: MSG_MISSING_IN_PERFORM)
      end

      private

      def deletes_attr_package_in_method_or_callees?(method_node, class_node)
        return true if method_deletes_attr_package?(method_node)

        called_method_names(method_node).any? do |name|
          callee = find_method_in_class(name, class_node)
          callee && method_deletes_attr_package?(callee)
        end
      end

      def called_method_names(method_node)
        method_node.each_descendant(:send).filter_map do |send_node|
          send_node.method_name if send_node.receiver.nil?
        end
      end

      def find_method_in_class(method_name, class_node)
        class_node.each_descendant(:def).find { |def_node| def_node.method?(method_name) }
      end

      def uses_attr_package?(node)
        node.each_descendant(:send).any? do |send_node|
          attr_package_receiver?(send_node.receiver)
        end
      end

      def find_perform_method(node)
        node.each_descendant(:def).find { |def_node| def_node.method?(:perform) }
      end

      def method_deletes_attr_package?(def_node)
        def_node.each_descendant(:send).any? do |send_node|
          send_node.method?(:delete) && attr_package_receiver?(send_node.receiver)
        end
      end
    end
  end
end
