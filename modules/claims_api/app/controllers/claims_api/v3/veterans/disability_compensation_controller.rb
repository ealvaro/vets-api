# frozen_string_literal: true

module ClaimsApi
  module V3
    module Veterans
      class DisabilityCompensationController < ClaimsApi::V3::ApplicationController
        FORM_NUMBER = '526'

        def submit
          render json: { errors: [{ status: '501', title: 'Not Implemented' }] }, status: :not_implemented
        end
      end
    end
  end
end
