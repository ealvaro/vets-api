# frozen_string_literal: true

module SignIn
  class OpenidConfigurationController < SignIn::ApplicationController
    skip_before_action :authenticate

    def show
      render json: SignIn::OpenidConfigurationPresenter.new.perform
    end
  end
end
