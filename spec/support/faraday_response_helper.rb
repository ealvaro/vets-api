# frozen_string_literal: true

module FaradayResponseHelper
  # Builds a Faraday::Response using a positional hash to avoid Ruby 3 keyword-arg warnings.
  #
  # Status defaults to 200 and MUST appear before body in the hash so that
  # Faraday::Env routes the :body key to :response_body (not :request_body).
  # Hash iteration order in Ruby is insertion order, so { status:, body: } is safe.
  def build_faraday_response(body, status: 200)
    Faraday::Response.new({ status:, body: })
  end
end

RSpec.configure do |config|
  config.include FaradayResponseHelper
end
