# frozen_string_literal: true

module RuboCop
  module Cop
    module Project
      class NoDirectTitleize < RuboCop::Cop::Base
        MSG = 'Do not call titleize/titlecase directly. For person or place names use ' \
              'StringHelpers.titlecase_name, which is safe with acronym inflections, ' \
              'hyphens, apostrophes, and nil. For non-name labels (service names, env ' \
              'labels, class-name derivation), add the file to this cop\'s Exclude list ' \
              'in .rubocop.yml.'

        RESTRICT_ON_SEND = %i[titleize titlecase].freeze

        def on_send(node)
          add_offense(node.loc.selector)
        end
        alias on_csend on_send
      end
    end
  end
end
