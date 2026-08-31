# frozen_string_literal: true

module AskVAApi
  module V0
    class PredictionsController < ApplicationController
      before_action :check_feature_flag # predictive-category-initiative

      # Shared request/response schema across prediction endpoints; only model_name varies
      PREDICTION_TYPES = {
        category: { model_name: 'Category' }
      }.freeze

      def category
        render_prediction(PREDICTION_TYPES[:category])
      end

      private

      def render_prediction(config)
        question = params.permit(:question)[:question]
        retriever = AskVAApi::Predictions::QuestionClassifiers::Retriever.new(question:, **config)
        result = retriever.call
        render json: result.payload, status: result.status
      end

      # Kill switch: checked per-request so it takes effect immediately, no restart needed
      def check_feature_flag
        return if Flipper.enabled?(:ask_va_predictive_category)

        render json: { error: { message: 'Not found' } }, status: :not_found
      end
    end
  end
end
