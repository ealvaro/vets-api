# frozen_string_literal: true

module ClaimsApi
  module V3
    class ApplicationController < ::ApplicationController
      service_tag 'lighthouse-claims'
      skip_before_action :verify_authenticity_token
      skip_after_action :set_csrf_header
    end
  end
end
