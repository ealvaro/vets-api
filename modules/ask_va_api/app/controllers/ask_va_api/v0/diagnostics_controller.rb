# frozen_string_literal: true

module AskVAApi
  module V0
    class DiagnosticsController < ApplicationController
      skip_before_action :authenticate

      def show
        crm_environment = Crm::Service.crm_env[Settings.vsp_environment.to_s]

        render json: { crm_environment: }, status: :ok
      end
    end
  end
end
