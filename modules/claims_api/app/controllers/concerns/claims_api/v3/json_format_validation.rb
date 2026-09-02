# frozen_string_literal: true

require 'oj'

module ClaimsApi
  module V3
    module JsonFormatValidation
      extend ActiveSupport::Concern

      included do
        def validate_json_format
          # rubocop:disable Style/ClassEqualityComparison
          # testing string b/c NullIO class doesn't always exist
          raise JSON::ParserError if request.body.class.name == 'Puma::NullIO'
          # rubocop:enable Style/ClassEqualityComparison

          raw_body = request.body.read
          @json_body = JSON.parse raw_body
          return if @json_body.is_a? Hash

          raise JSON::ParserError
        rescue JSON::ParserError
          render_body_is_not_a_hash_error(raw_body)
        end

        def render_body_is_not_a_hash_error(body)
          status = '422'
          error = {
            title: 'Unprocessable entity',
            status:,
            detail: "The request body is not a valid JSON object: #{get_error_message(body)}",
            source: error_message_source(body)
          }
          render status:, json: { errors: [error] }
        end

        def get_error_message(body)
          Oj.load(body)
        rescue Oj::ParseError => e
          e&.to_s&.gsub('.', '/')&.split(', column')&.[](0) # cutoff some unneeded details
        end

        def error_message_source(body)
          {
            pointer: get_error_message(body)&.split('after ', 2)&.[](1)&.gsub(')', '') # get the data/attributes path
          }
        end
      end
    end
  end
end
