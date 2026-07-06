# frozen_string_literal: true

module AccreditedRepresentativePortal
  module V0
    class ApidocsController < ApplicationController
      service_tag 'accredited-representative-portal'

      skip_before_action :authenticate
      skip_after_action :verify_pundit_authorization

      def index
        swagger = JSON.parse(
          File.read(AccreditedRepresentativePortal::Engine.root.join('app/swagger/v0/swagger.json'))
        )
        render json: swagger
      end
    end
  end
end
