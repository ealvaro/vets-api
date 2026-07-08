# frozen_string_literal: true

require 'lgy/service'
require 'mobile/v0/lgy/configuration'

module Mobile
  module V0
    module Lgy
      ##
      # Class responsible for the LGY (Loan Guaranty) COE API interface for mobile.
      # Overrides the configuration class member to inject mobile-specific
      # credentials so LGY can distinguish mobile traffic from web traffic.
      #
      class Service < ::LGY::Service
        configuration Mobile::V0::Lgy::Configuration
      end
    end
  end
end
