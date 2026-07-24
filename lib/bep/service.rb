# frozen_string_literal: true

require 'bep/configuration'
require 'common/client/base'

module BEP
  class Service < Common::Client::Base
    include Common::Client::Concerns::Monitoring
  end
end
