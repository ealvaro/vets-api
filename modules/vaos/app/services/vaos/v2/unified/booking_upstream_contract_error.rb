# frozen_string_literal: true

require 'common/exceptions'

module VAOS
  module V2
    module Unified
      ##
      # Raised when VA/EPS returns a nominally successful response that does not satisfy
      # our booking contract (e.g. missing appointment id, malformed confirmation). Maps to HTTP 502.
      #
      class BookingUpstreamContractError < Common::Exceptions::BackendServiceException
        def initialize(detail)
          super('VAOS_502', { detail: }, 502, detail)
        end
      end
    end
  end
end
