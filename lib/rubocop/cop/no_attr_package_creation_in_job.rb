# frozen_string_literal: true

require_relative 'attr_package_helpers'

module RuboCop
  module Cop
    class NoAttrPackageCreationInJob < RuboCop::Cop::Base
      include AttrPackageHelpers

      MSG = 'Do not create Sidekiq::AttrPackage inside a job. ' \
            "Create it at the entry point and pass only the cache_key. See #{DOC_URL}.".freeze

      RESTRICT_ON_SEND = %i[create].freeze

      def on_send(node)
        return unless attr_package_receiver?(node.receiver)
        return unless inside_any_method?(node)
        return unless node.each_ancestor(:class).any? { |c| sidekiq_job_class?(c) }
        return if key_passed_to_different_job?(node)

        add_offense(node)
      end

      def inside_any_method?(node)
        node.each_ancestor(:def, :defs).any?
      end

      private

      def key_passed_to_different_job?(create_node)
        assignment = create_node.each_ancestor(:lvasgn).first
        return false unless assignment

        assigned_var = assignment.children.first
        method_node = create_node.each_ancestor(:def, :defs).first
        return false unless method_node

        method_node.each_descendant(:send).any? do |send_node|
          send_node.method?(:perform_async) &&
            send_node.receiver&.const_type? &&
            send_node.arguments.any? do |arg|
              arg.lvar_type? && arg.children.first == assigned_var
            end
        end
      end
    end
  end
end
