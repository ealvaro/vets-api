# frozen_string_literal: true

require 'dgi/configuration'
require 'common/client/base'

module MebApi
  module DGI
    class Service < Common::Client::Base
      include Common::Client::Concerns::Monitoring

      def initialize(user)
        @user = user
      end

      private

      # Normalizes claim type to match DGI enum expectations.
      # VetTec must preserve exact casing; other types are capitalized.
      def normalize_claim_type(type)
        normalized = type.to_s
        normalized.casecmp('VetTec').zero? ? 'VetTec' : normalized.capitalize
      end
    end
  end
end
