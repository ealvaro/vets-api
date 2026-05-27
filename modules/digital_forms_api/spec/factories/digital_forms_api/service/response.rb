# frozen_string_literal: true

# Factories for mocking upstream Forms API HTTP responses.
# Error traits stub Common::Client::Errors::ClientError with realistic BIP
# framework body shapes so the controller's error-mapping logic can be
# exercised end-to-end without VCR cassettes.

FactoryBot.define do
  factory :digital_forms_service_response, class: 'OpenStruct' do
    # 200 OK — submission retrieved successfully
    trait :success do
      reason_phrase { 'OK' }
      status { 200 }
      body do
        {
          'submission' => {
            'submissionId' => 'a1ba50e4-e689-4852-bec7-2a66519f0ed3',
            'claimId' => '123456789'
          }
        }
      end
    end
  end

  factory :digital_forms_service_error, class: 'Common::Client::Errors::ClientError' do
    initialize_with { new(message, status, body) }
    message { 'VEFSERR_TEST' }

    # ---- 4xx Client Errors ----

    # 400 Bad Request — malformed or invalid request payload
    trait :bad_request do
      status { 400 }
      body do
        { 'messages' => [{
          'timestamp' => '2024-05-20T15:53:29.389',
          'key' => 'bip.framework.validation.error',
          'severity' => 'ERROR',
          'status' => 400,
          'text' => 'Invalid request: missing required field.'
        }] }
      end
    end

    # 401 Unauthorized — missing or invalid JWT / authentication credentials
    trait :unauthorized do
      status { 401 }
      body { { 'message' => 'Unauthorized: invalid or expired token.' } }
    end

    # 403 Forbidden — valid credentials but insufficient permissions (multiple BIP messages)
    trait :multiple do
      status { 403 }
      body do
        { 'messages' => [
          {
            'key' => 'bip.framework.not.authorized.exception',
            'severity' => 'ERROR',
            'status' => 403,
            'text' => 'Access denied.',
            'timestamp' => '2019-08-29T18:40:22.766Z'
          },
          {
            'timestamp' => '2024-05-20T15:53:29.389',
            'key' => 'bip.framework.service.teapot',
            'severity' => 'ERROR',
            'status' => 418,
            'text' => 'I am a teapot.'
          }
        ] }
      end
    end

    # 404 Not Found — requested submission does not exist
    trait :not_found do
      status { 404 }
      body { { 'message' => 'Submission not found.' } }
    end

    # 408 Request Timeout — upstream service did not respond in time
    trait :request_timeout do
      status { 408 }
      body do
        { 'messages' => [{
          'timestamp' => '2024-05-20T15:53:29.389',
          'key' => 'bip.framework.request.timeout',
          'severity' => 'ERROR',
          'status' => 408,
          'text' => 'The request timed out waiting for a response.'
        }] }
      end
    end

    # 418 I'm a teapot — unexpected single-message BIP error (kept for backwards compatibility)
    trait :single do
      status { 418 }
      body do
        { 'messages' => [{
          'timestamp' => '2024-05-20T15:53:29.389',
          'key' => 'bip.framework.service.teapot',
          'severity' => 'ERROR',
          'status' => 418,
          'text' => 'I am a teapot.'
        }] }
      end
    end

    # 422 Unprocessable Entity — request is syntactically valid but semantically incorrect
    trait :unprocessable_entity do
      status { 422 }
      body do
        { 'messages' => [{
          'timestamp' => '2024-05-20T15:53:29.389',
          'key' => 'bip.framework.validation.unprocessable',
          'severity' => 'ERROR',
          'status' => 422,
          'text' => 'Unprocessable entity: veteranId format is invalid.'
        }] }
      end
    end

    # 429 Too Many Requests — rate limit exceeded
    trait :too_many_requests do
      status { 429 }
      body do
        { 'messages' => [{
          'timestamp' => '2024-05-20T15:53:29.389',
          'key' => 'bip.framework.rate.limit.exceeded',
          'severity' => 'ERROR',
          'status' => 429,
          'text' => 'Rate limit exceeded. Please retry after a brief wait.'
        }] }
      end
    end

    # ---- 5xx Server Errors ----

    # 500 Internal Server Error — unexpected upstream failure
    trait :internal_server_error do
      status { 500 }
      body { { 'message' => 'An unexpected error occurred.' } }
    end

    # 502 Bad Gateway — upstream dependency returned an invalid response
    trait :bad_gateway do
      status { 502 }
      body { { 'message' => 'Bad gateway: upstream service returned an invalid response.' } }
    end

    # 503 Service Unavailable — upstream service is temporarily offline
    trait :error do
      status { 503 }
      body { { 'message' => 'Service unavailable.' } }
    end

    # 504 Gateway Timeout — upstream dependency timed out
    trait :gateway_timeout do
      status { 504 }
      body do
        { 'messages' => [{
          'timestamp' => '2024-05-20T15:53:29.389',
          'key' => 'bip.framework.gateway.timeout',
          'severity' => 'ERROR',
          'status' => 504,
          'text' => 'Gateway timeout: the upstream service did not respond.'
        }] }
      end
    end
  end
end
