# frozen_string_literal: true

module MHV
  module UserAccount
    module Errors
      class UserAccountError < StandardError
        def as_json
          message.split(',').map { |m| { title: class_name, detail: m.strip } }
        end

        private

        def class_name
          self.class.name.demodulize.underscore.humanize
        end
      end

      class CreatorError < UserAccountError; end

      class ValidationError < UserAccountError; end

      class MHVClientError < UserAccountError
        attr_accessor :body

        def initialize(message, body = nil)
          super(message)
          @body = body
        end

        def as_json
          data = body.is_a?(Hash) ? body : {}
          [{ title: message, detail: data['message'], code: data['errorCode'] }]
        end
      end
    end
  end
end
