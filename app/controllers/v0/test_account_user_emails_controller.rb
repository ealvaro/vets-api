# frozen_string_literal: true

module V0
  class TestAccountUserEmailsController < ApplicationController
    service_tag 'identity'
    skip_before_action :authenticate

    def create
      create_params

      head :created
    rescue
      render json: { errors: 'invalid params' }, status: :bad_request
    end

    def create_params
      params.require(:email)
    end
  end
end
