# frozen_string_literal: true

module DigitalFormsApi
  # Wraps the Forms API (BIP) submission-retrieval response and exposes intent-named
  # accessors for the pieces the controller consumes, isolating the upstream `envelope`
  # shape in one place instead of scattering `response.body.dig('envelope', ...)` through
  # the controller.
  #
  # Introduced per ADR-0002 §1 as the behavior-preserving first slice: it surfaces only
  # what is read today and performs the same lookups the controller did inline. The fuller
  # form-agnostic responsibilities described in the ADR (plugin resolution, template
  # translation) are later, separate work.
  class SubmissionResponse
    # @param response [#body] the retrieve response (a Faraday::Env; only its #body is read) from Service::Submissions#retrieve
    def initialize(response)
      @response = response
    end

    # The veteran identifier object from the BIP envelope, used to authorize access.
    # @return [Hash, Object, nil] the raw veteranId — a Hash when well-formed
    def veteran_id
      body.dig('envelope', 'veteranId')
    end

    # The submitted form payload from the BIP envelope, echoed back to the client.
    # @return [Hash, nil] the form payload
    def payload
      body.dig('envelope', 'payload')
    end

    private

    # The parsed upstream response body (delegates to the underlying service response).
    # @return [Hash] the response body
    def body
      @response.body
    end
  end
end
