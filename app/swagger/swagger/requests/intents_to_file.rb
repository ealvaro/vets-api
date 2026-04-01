# frozen_string_literal: true

module Swagger
  module Requests
    class IntentsToFile
      include Swagger::Blocks

      swagger_path '/v0/intents_to_file' do
        operation :get do
          extend Swagger::Responses::AuthenticationError

          key :description, 'Get all active Intent to File records across compensation, pension, and survivor types'
          key :operationId, 'getIntentsToFile'
          key :tags, %w[intents_to_file]

          parameter :authorization

          response 200 do
            key :description, 'Response is OK'
            schema do
              property :data, type: :array do
                items do
                  property :id, type: :string, example: '193685'
                  property :type, type: :string, example: 'compensation'
                  property :creation_date, type: :string, example: '2025-03-16T19:15:21.000-05:00'
                  property :expiration_date, type: :string, example: '2026-03-16T19:15:20.000-05:00'
                  property :status, type: :string, example: 'active'
                end
              end
            end
          end
        end
      end
    end
  end
end
