# frozen_string_literal: true

module AskVAApi
  module Predictions
    module QuestionClassifiers
      class Retriever
        include ActionView::Helpers::SanitizeHelper

        MAX_QUESTION_LENGTH = 10_000

        class ValidationError < StandardError; end

        attr_reader :question

        def initialize(question:, model_name:)
          @question = question
          @model_name = model_name
          @service_client = ServiceClient.new
        end

        def call
          validate_input!
          clean_question = sanitize_question(@question)
          response_data = @service_client.predict(model_name: @model_name, question: clean_question)
          serialized_data = Serializer.new(response_data).call

          Result.new(payload: serialized_data, status: :ok)
        rescue ValidationError => e
          Result.new(
            payload: { error: { message: e.message } },
            status: :unprocessable_entity
          )
        rescue PredictionServiceError => e
          handle_service_error(e)
        rescue => e
          Rails.logger.error('AskVA Predictions Retriever Error', { error: e.message })
          Result.new(
            payload: { error: { message: 'An unexpected error occurred' } },
            status: :internal_server_error
          )
        end

        private

        def validate_input!
          raise ValidationError, 'Question is required' if @question.blank?

          if @question.length > MAX_QUESTION_LENGTH
            raise ValidationError, "Question cannot exceed #{MAX_QUESTION_LENGTH} characters"
          end
        end

        def sanitize_question(text)
          sanitize(text, tags: [])
        end

        def handle_service_error(error)
          status = case error.status
                   when 422
                     :unprocessable_entity
                   when 502, 503
                     :bad_gateway
                   when 504
                     :gateway_timeout
                   else
                     :internal_server_error
                   end

          Result.new(
            payload: { error: { message: error.message } },
            status:
          )
        end

        Result = Struct.new(:payload, :status, keyword_init: true)
      end
    end
  end
end
