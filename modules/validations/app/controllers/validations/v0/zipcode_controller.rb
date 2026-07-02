# frozen_string_literal: true

require 'validations/validator/zipcode_validator'

module Validations
  module V0
    # Controller for zipcode validation endpoints
    #
    # Provides HTTP access to zipcode validation functionality
    class ZipcodeController < ApplicationController
      skip_before_action :authenticate

      service_tag 'validations.v0.zipcode'

      # GET /validations/v0/zipcode/:zipcode
      def validate
        zipcode = params[:zipcode].to_s.strip
        validation = Validations::Validator::ZipcodeValidator.validate(zipcode)

        render json: validation
      end
    end
  end
end
