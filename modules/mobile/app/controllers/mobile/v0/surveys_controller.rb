# frozen_string_literal: true

module Mobile
  module V0
    class SurveysController < ApplicationController
      def create
        survey_response = Mobile::SurveyResponse.new(
          survey_type: survey_params[:survey_type],
          user_uuid: current_user.uuid,
          survey_data: survey_params[:survey_data],
          metadata: survey_params[:metadata]
        )

        raise Common::Exceptions::ValidationErrors, survey_response unless survey_response.valid?

        survey_response.save!
        head :no_content
      end

      private

      def survey_params
        params.permit(
          :survey_type,
          survey_data: {},
          metadata: {}
        )
      end
    end
  end
end
