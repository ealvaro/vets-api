# frozen_string_literal: true

module RuboCop
  module Cop
    module Project
      # Forbids using Flipper.enable/disable in specs because these methods
      # mutate global feature state and can create test pollution.
      class ForbidFlipperToggleInSpecs < RuboCop::Cop::Base
        MSG = 'Avoid Flipper.enable/disable in specs. ' \
              'Stub Flipper.enabled? (for example, ' \
              'allow(Flipper).to receive(:enabled?).with(:feature).and_return(true)). ' \
              'For multiple flags, add one enabled? stub per flag. ' \
              'If other flags should fall through, call ' \
              'allow(Flipper).to receive(:enabled?).and_call_original first. ' \
              'Add # rubocop:disable with a comment only if the spec is testing the toggle mechanism itself.'

        RESTRICT_ON_SEND = %i[enable disable].freeze

        def on_send(node)
          return unless in_spec_file?
          return unless flipper_toggle_call?(node)

          add_offense(node.loc.selector)
        end

        private

        def flipper_toggle_call?(node)
          receiver = node.receiver
          receiver&.const_type? && receiver.const_name == 'Flipper'
        end

        def in_spec_file?
          processed_source.file_path.match?(%r{(^|/)spec/})
        end
      end
    end
  end
end
