# frozen_string_literal: true

require_relative 'attr_package_helpers'

module RuboCop
  module Cop
    class AttrPackageDeleteAfterRetry < RuboCop::Cop::Base
      include AttrPackageHelpers

      MSG_MISSING = 'Jobs using Sidekiq::AttrPackage must define sidekiq_retries_exhausted ' \
                    "to clean up the cache key after terminal failure. See #{DOC_URL}.".freeze
      MSG_NO_DELETE = 'sidekiq_retries_exhausted must call Sidekiq::AttrPackage.delete ' \
                      "to clean up the cache key. See #{DOC_URL}.".freeze

      def on_class(node)
        return unless sidekiq_job_class?(node)
        return unless uses_attr_package?(node)

        retries_block = find_retries_exhausted_block(node)

        if retries_block.nil?
          add_offense(node.loc.name, message: MSG_MISSING)
        elsif !block_deletes_attr_package?(retries_block)
          add_offense(retries_block.send_node, message: MSG_NO_DELETE)
        end
      end

      private

      def uses_attr_package?(node)
        node.each_descendant(:send).any? do |send_node|
          attr_package_receiver?(send_node.receiver)
        end
      end

      def find_retries_exhausted_block(node)
        node.each_descendant(:block).find do |block_node|
          block_node.send_node&.method?(:sidekiq_retries_exhausted)
        end
      end

      def block_deletes_attr_package?(block_node)
        block_node.each_descendant(:send).any? do |send_node|
          send_node.method?(:delete) && attr_package_receiver?(send_node.receiver)
        end
      end
    end
  end
end
