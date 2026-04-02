# frozen_string_literal: true

module RuboCop
  module Cop
    module AttrPackageHelpers
      DOC_URL = 'https://depo-platform-documentation.scrollhelp.site/developer-docs/sidekiq-attrpackage-guidelines'

      private

      def attr_package_receiver?(node)
        const_name(node) == 'Sidekiq::AttrPackage'
      end

      def const_name(node)
        return unless node&.const_type?

        parts = []
        current = node
        while current&.const_type?
          parts.unshift(current.children[1].to_s)
          current = current.children[0]
        end
        parts.join('::')
      end

      def sidekiq_job_class?(node)
        node.each_descendant(:send).any? do |send_node|
          send_node.method?(:include) &&
            send_node.arguments.any? do |arg|
              %w[Sidekiq::Job Sidekiq::Worker].include?(const_name(arg))
            end
        end
      end
    end
  end
end
