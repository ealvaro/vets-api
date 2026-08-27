# frozen_string_literal: true

require_relative 'attr_package_helpers'

module RuboCop
  module Cop
    class NoTimeoutInSidekiqJob < RuboCop::Cop::Base
      include AttrPackageHelpers

      MSG = 'Avoid Timeout.timeout in Sidekiq jobs. It raises inside a thread and can corrupt ' \
            'shared connections, causing unrelated jobs to fail. Use per-operation timeouts ' \
            '(e.g., Net::HTTP read_timeout) instead. ' \
            'See https://www.mikeperham.com/2015/05/08/timeout-rubys-most-dangerous-api/'

      RESTRICT_ON_SEND = %i[timeout].freeze

      def on_send(node)
        return unless timeout_module?(node.receiver)
        return unless node.each_ancestor(:class).any? { |c| sidekiq_job_class?(c) }

        add_offense(node)
      end

      private

      def timeout_module?(node)
        const_name(node) == 'Timeout'
      end
    end
  end
end
