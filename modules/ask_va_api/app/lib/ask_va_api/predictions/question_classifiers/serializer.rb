# frozen_string_literal: true

module AskVAApi
  module Predictions
    module QuestionClassifiers
      class Serializer
        def initialize(prediction_data)
          @prediction_data = prediction_data
        end

        def call
          transform_response(@prediction_data)
        end

        private

        def transform_response(data)
          return data if data.blank?

          {
            modelName: data['model_name'],
            modelVersion: data['model_version'],
            error: data['error'],
            predictions: transform_predictions(data['predictions'])
          }.compact
        end

        def transform_predictions(predictions)
          return nil if predictions.blank?

          predictions.transform_values { |prediction| transform_prediction(prediction) }
        end

        def transform_prediction(prediction)
          {
            confidenceLevel: prediction['confidence_level'],
            name: prediction['name'],
            modelId: prediction['model_id'],
            category: transform_category(prediction['category'])
          }.compact
        end

        def transform_category(category)
          return nil if category.blank?

          {
            id: category['id'],
            name: category['name'],
            description: category['description']
          }.compact
        end
      end
    end
  end
end
