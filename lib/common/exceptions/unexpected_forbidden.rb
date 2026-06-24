# frozen_string_literal: true

require 'common/exceptions/forbidden'

module Common
  module Exceptions
    # Forbidden is not reportable. This exception is a duplicate that IS reportable
    class UnexpectedForbidden < Forbidden
      def i18n_key
        "common.exceptions.#{self.class.superclass.name.split('::').last.underscore}"
      end
    end
  end
end
