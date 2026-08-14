# frozen_string_literal: true

require 'rails_helper'
require 'idp/client'

RSpec.describe 'CAVE API', type: :request do
  subject(:parsed_response) { JSON.parse(response.body) }

  let(:client) { instance_double(Idp::Client) }
  let(:user) { create(:user, :loa3) }
  let(:idp_user_id) { user.user_account_uuid || user.uuid }

  def idp_error(message: 'boom', **)
    Idp::Error.new(message, **)
  end

  before do
    allow(Flipper).to receive(:enabled?).and_call_original
    allow(Flipper).to receive(:enabled?).with(:cave_idp).and_return(true)
    allow(Idp).to receive(:client).and_return(client)
  end

  describe 'feature flags' do
    before { sign_in_as(user) }

    it 'returns 404 when cave_idp is disabled' do
      allow(Flipper).to receive(:enabled?).with(:cave_idp).and_return(false)

      post '/v0/cave', params: { pdf_b64: 'ZmlsZQ==', file_name: 'test.pdf' }

      expect(response).to have_http_status(:not_found)
    end
  end

  describe 'POST /v0/cave' do
    let(:params) { { pdf_b64: 'ZmlsZQ==', file_name: 'test.pdf' } }

    it 'returns 401 when unauthenticated' do
      post('/v0/cave', params:)

      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns the upstream payload' do
      sign_in_as(user)
      allow(client).to receive(:intake).with(file_name: 'test.pdf', pdf_base64: 'ZmlsZQ==', user_id: idp_user_id)
                                       .and_return('id' => 'abc123')

      post('/v0/cave', params:)

      expect(response).to have_http_status(:ok)
      expect(parsed_response['id']).to eq('abc123')
    end

    it 'preserves actionable upstream intake validation failures' do
      sign_in_as(user)
      allow(client).to receive(:intake).and_raise(
        idp_error(
          upstream_status: 400,
          upstream_body: { 'error' => 'Invalid PDF payload' },
          operation: 'intake',
          failure_category: 'upstream_response'
        )
      )

      post('/v0/cave', params:)

      expect(response).to have_http_status(:bad_request)
      expect(parsed_response['errors'].first).to include(
        'code' => 'idp_bad_request',
        'status' => '400',
        'detail' => 'Invalid PDF payload'
      )
    end

    it 'validates required params' do
      sign_in_as(user)

      post '/v0/cave', params: { pdf_b64: 'oops' }

      expect(response).to have_http_status(:bad_request)
    end
  end

  describe 'GET /v0/cave/:id/status' do
    it 'returns 401 when unauthenticated' do
      get '/v0/cave/abc123/status'

      expect(response).to have_http_status(:unauthorized)
    end

    it 'proxies the status call and meters a completed scan_status as success' do
      sign_in_as(user)
      allow(client).to receive(:status).with('abc123', user_id: idp_user_id).and_return('scan_status' => 'completed')

      expect { get '/v0/cave/abc123/status' }
        .to trigger_statsd_increment('api.cave.status.success')

      expect(response).to have_http_status(:ok)
      expect(parsed_response['scan_status']).to eq('completed')
    end

    # A pending poll must not inflate `.success`: the frontend polls `status` repeatedly while a
    # doc is pending, so pending gets its own bucket and `.success` reflects real completions only.
    it 'forwards a pending scan_status and meters it separately from success' do
      sign_in_as(user)
      allow(client).to receive(:status).with('abc123', user_id: idp_user_id).and_return('scan_status' => 'pending')

      expect { get '/v0/cave/abc123/status' }
        .to trigger_statsd_increment('api.cave.status.pending')
        .and not_trigger_statsd_increment('api.cave.status.success')

      expect(response).to have_http_status(:ok)
      expect(parsed_response['scan_status']).to eq('pending')
    end

    # A `failed` scan_status is a TERMINAL 2xx result, not a 5xx: the frontend poller treats 5xx
    # as retryable and only stops on a terminal scanStatus in a 2xx body. So `failed` returns 200
    # with the failure conveyed in the body (still logged + metered), never a 502.
    it 'returns a failed scan_status as a 200 passthrough (not a retryable 502)' do
      sign_in_as(user)
      allow(client).to receive(:status).with('abc123', user_id: idp_user_id).and_return(
        'scan_status' => 'failed',
        'error' => { 'error_message' => 'Unable to classify document' }
      )

      expect { get '/v0/cave/abc123/status' }
        .to trigger_statsd_increment('api.cave.status.failed')

      expect(response).to have_http_status(:ok)
      expect(parsed_response['scan_status']).to eq('failed')
      expect(parsed_response['error']).to eq('error_message' => 'Unable to classify document')
    end

    it 'logs the failed outcome while passing the body through' do
      sign_in_as(user)
      allow(client).to receive(:status).with('abc123', user_id: idp_user_id).and_return(
        'scan_status' => 'failed',
        'error' => { 'error_message' => 'Unable to classify document' }
      )
      allow(Rails.logger).to receive(:info)

      get '/v0/cave/abc123/status'

      expect(Rails.logger).to have_received(:info)
        .with('[CaveController] CAVE outcome', hash_including(scan_status: 'failed'))
    end

    it 'forwards completed_with_errors as 200 preserving structured warnings' do
      sign_in_as(user)
      allow(client).to receive(:status).with('abc123', user_id: idp_user_id).and_return(
        'scan_status' => 'completed_with_errors',
        'warnings' => [{ 'warning_message' => 'Low confidence on DATE_OF_BIRTH' }]
      )

      expect { get '/v0/cave/abc123/status' }
        .to trigger_statsd_increment('api.cave.status.completed_with_warnings')

      expect(response).to have_http_status(:ok)
      expect(parsed_response['scan_status']).to eq('completed_with_errors')
      expect(parsed_response['warnings']).to eq([{ 'warning_message' => 'Low confidence on DATE_OF_BIRTH' }])
    end

    it 'wraps a single Hash warnings value in an array WITHOUT flattening it to key/value pairs' do
      sign_in_as(user)
      allow(client).to receive(:status).with('abc123', user_id: idp_user_id).and_return(
        'scan_status' => 'completed_with_errors',
        'warnings' => { 'step' => 'extraction', 'warning_message' => 'Low confidence' }
      )

      get '/v0/cave/abc123/status'

      expect(response).to have_http_status(:ok)
      # the structured Hash stays a Hash inside a one-element array, NOT [["step",...],...]
      expect(parsed_response['warnings']).to eq(
        [{ 'step' => 'extraction', 'warning_message' => 'Low confidence' }]
      )
    end

    it 'rejects a missing scan_status with a logged 502' do
      sign_in_as(user)
      allow(client).to receive(:status).with('abc123', user_id: idp_user_id).and_return('id' => 'abc123')
      allow(Rails.logger).to receive(:error)

      expect { get '/v0/cave/abc123/status' }
        .to trigger_statsd_increment('api.cave.status.invalid_scan_status')

      expect(response).to have_http_status(:bad_gateway)
      expect(Rails.logger).to have_received(:error).with('[CaveController] invalid CAVE scan_status', anything)
    end

    it 'rejects an unrecognized scan_status value with a 502' do
      sign_in_as(user)
      allow(client).to receive(:status).with('abc123', user_id: idp_user_id).and_return('scan_status' => 'bogus')

      get '/v0/cave/abc123/status'

      expect(response).to have_http_status(:bad_gateway)
    end

    it 'preserves actionable upstream not found errors' do
      sign_in_as(user)
      allow(client).to receive(:status).with('abc123', user_id: idp_user_id).and_raise(
        idp_error(
          upstream_status: 404,
          upstream_body: { 'error' => 'Item not found.' },
          operation: 'status',
          failure_category: 'upstream_response'
        )
      )

      get '/v0/cave/abc123/status'

      expect(response).to have_http_status(:not_found)
      expect(parsed_response['errors'].first).to include(
        'code' => 'idp_not_found',
        'status' => '404',
        'detail' => 'Item not found.'
      )
    end

    it 'keeps upstream auth failures generic for website session handling' do
      sign_in_as(user)
      allow(client).to receive(:status).with('abc123', user_id: idp_user_id).and_raise(
        idp_error(
          upstream_status: 401,
          upstream_body: { 'error' => 'Missing IDP auth headers' },
          operation: 'status',
          failure_category: 'upstream_response'
        )
      )

      get '/v0/cave/abc123/status'

      expect(response).to have_http_status(:bad_gateway)
      expect(parsed_response['errors'].first).to include(
        'code' => 'idp_upstream_auth_error',
        'status' => '502',
        'detail' => 'Document processing service is temporarily unavailable'
      )
    end
  end

  describe 'GET /v0/cave/:id/output' do
    it 'returns 401 when unauthenticated' do
      get '/v0/cave/abc123/output'

      expect(response).to have_http_status(:unauthorized)
    end

    # `output` returns the extracted `forms` payload, which carries NO top-level scan_status;
    # scan_status envelope validation applies only to `status`. `output` is guarded by
    # payload-shape validation (non-empty Hash) instead.
    it 'defaults the type to artifact' do
      sign_in_as(user)
      allow(client).to receive(:output).with('abc123', type: 'artifact', user_id: idp_user_id)
                                       .and_return('forms' => [{ 'mmsFormValidationId' => 'form-1' }])

      get '/v0/cave/abc123/output'

      expect(response).to have_http_status(:ok)
      expect(parsed_response['forms']).to eq([{ 'mmsFormValidationId' => 'form-1' }])
    end

    it 'uses provided type' do
      sign_in_as(user)
      allow(client).to receive(:output).with('abc123', type: 'form', user_id: idp_user_id)
                                       .and_return('forms' => [{ 'mmsFormValidationId' => 'form-1' }])

      get '/v0/cave/abc123/output', params: { type: 'form' }

      expect(response).to have_http_status(:ok)
    end

    it 'meters a successful output response' do
      sign_in_as(user)
      allow(client).to receive(:output).with('abc123', type: 'artifact', user_id: idp_user_id)
                                       .and_return('forms' => [])

      expect { get '/v0/cave/abc123/output' }
        .to trigger_statsd_increment('api.cave.output.success')
    end

    it 'rejects a malformed (non-Hash) output payload with a 502' do
      sign_in_as(user)
      allow(client).to receive(:output).with('abc123', type: 'artifact', user_id: idp_user_id).and_return([])

      expect { get '/v0/cave/abc123/output' }
        .to trigger_statsd_increment('api.cave.output.invalid_payload')

      expect(response).to have_http_status(:bad_gateway)
    end

    it 'keeps transport failures generic' do
      sign_in_as(user)
      allow(client).to receive(:output).with('abc123', type: 'artifact', user_id: idp_user_id).and_raise(
        idp_error(operation: 'output', failure_category: 'transport')
      )

      get '/v0/cave/abc123/output'

      expect(response).to have_http_status(:bad_gateway)
      expect(parsed_response['errors'].first).to include(
        'code' => 'idp_transport_error',
        'status' => '502',
        'detail' => 'Document processing service is temporarily unavailable'
      )
    end
  end

  describe 'GET /v0/cave/:id/download' do
    it 'returns 401 when unauthenticated' do
      get '/v0/cave/abc123/download', params: { kvpid: 'kvp1' }

      expect(response).to have_http_status(:unauthorized)
    end

    it 'requires kvpid' do
      sign_in_as(user)

      get '/v0/cave/abc123/download'

      expect(response).to have_http_status(:bad_request)
    end

    it 'proxies the download call' do
      sign_in_as(user)
      allow(client).to receive(:download).with('abc123', kvpid: 'kvp1', user_id: idp_user_id).and_return('data' => {})

      get '/v0/cave/abc123/download', params: { kvpid: 'kvp1' }

      expect(response).to have_http_status(:ok)
    end

    it 'persists the OCR response with the CAVE document id, kvpid, and user id' do
      sign_in_as(user)
      allow(client).to receive(:download).with('abc123', kvpid: 'kvp1', user_id: idp_user_id).and_return('data' => {})

      expect { get '/v0/cave/abc123/download', params: { kvpid: 'kvp1' } }
        .to change(CaveSubmission, :count).by(1)

      submission = CaveSubmission.last
      expect(submission.cave_document_id).to eq('abc123')
      expect(submission.kvpid).to eq('kvp1')
      expect(submission.idp_user_id).to eq(idp_user_id)
    end

    it 'meters a successful download persist' do
      sign_in_as(user)
      allow(client).to receive(:download).with('abc123', kvpid: 'kvp1', user_id: idp_user_id)
                                         .and_return('FIRST_NAME' => 'Ada')

      expect { get '/v0/cave/abc123/download', params: { kvpid: 'kvp1' } }
        .to trigger_statsd_increment('api.cave.download.success')
    end

    it 'rejects a malformed (non-Hash) download payload with a 502 instead of persisting it' do
      sign_in_as(user)
      allow(client).to receive(:download).with('abc123', kvpid: 'kvp1', user_id: idp_user_id).and_return([])
      allow(Rails.logger).to receive(:error)

      expect do
        expect { get '/v0/cave/abc123/download', params: { kvpid: 'kvp1' } }
          .to trigger_statsd_increment('api.cave.download.invalid_payload')
      end.not_to change(CaveSubmission, :count)

      expect(response).to have_http_status(:bad_gateway)
    end

    it 'rejects an empty-Hash download payload with a 502' do
      sign_in_as(user)
      allow(client).to receive(:download).with('abc123', kvpid: 'kvp1', user_id: idp_user_id).and_return({})

      expect { get '/v0/cave/abc123/download', params: { kvpid: 'kvp1' } }
        .not_to change(CaveSubmission, :count)

      expect(response).to have_http_status(:bad_gateway)
    end

    it 'preserves actionable upstream ownership failures' do
      sign_in_as(user)
      allow(client).to receive(:download).with('abc123', kvpid: 'kvp1', user_id: idp_user_id).and_raise(
        idp_error(
          upstream_status: 403,
          upstream_body: { 'error' => 'Forbidden' },
          operation: 'download',
          failure_category: 'upstream_response'
        )
      )

      get '/v0/cave/abc123/download', params: { kvpid: 'kvp1' }

      expect(response).to have_http_status(:forbidden)
      expect(parsed_response['errors'].first).to include(
        'code' => 'idp_forbidden',
        'status' => '403',
        'detail' => 'Forbidden'
      )
    end
  end

  describe 'POST /v0/cave/:id/update' do
    let(:payload) { { 'FIRST_NAME' => 'Ada', 'LAST_NAME' => 'Lovelace' } }
    let(:json_headers) { { 'CONTENT_TYPE' => 'application/json' } }

    it 'returns 401 when unauthenticated' do
      post '/v0/cave/abc123/update?kvpid=kvp1', params: payload.to_json, headers: json_headers

      expect(response).to have_http_status(:unauthorized)
    end

    it 'requires kvpid' do
      sign_in_as(user)

      post '/v0/cave/abc123/update', params: payload.to_json, headers: json_headers

      expect(response).to have_http_status(:bad_request)
    end

    it 'requires a valid JSON object body' do
      sign_in_as(user)

      post '/v0/cave/abc123/update?kvpid=kvp1', params: '[]', headers: json_headers

      expect(response).to have_http_status(:bad_request)
    end

    it 'proxies the update call' do
      sign_in_as(user)
      allow(client).to receive(:update)
        .with('abc123', kvpid: 'kvp1', payload:, user_id: idp_user_id)
        .and_return(payload)

      post '/v0/cave/abc123/update?kvpid=kvp1', params: payload.to_json, headers: json_headers

      expect(response).to have_http_status(:ok)
      expect(parsed_response).to eq(payload)
    end

    it 'meters a successful update' do
      sign_in_as(user)
      allow(client).to receive(:update)
        .with('abc123', kvpid: 'kvp1', payload:, user_id: idp_user_id)
        .and_return(payload)

      expect { post '/v0/cave/abc123/update?kvpid=kvp1', params: payload.to_json, headers: json_headers }
        .to trigger_statsd_increment('api.cave.update.success')
    end

    it 'treats an empty-object update echo as a successful mutation' do
      sign_in_as(user)
      allow(client).to receive(:update)
        .with('abc123', kvpid: 'kvp1', payload:, user_id: idp_user_id)
        .and_return({})

      expect { post '/v0/cave/abc123/update?kvpid=kvp1', params: payload.to_json, headers: json_headers }
        .to trigger_statsd_increment('api.cave.update.success')

      expect(response).to have_http_status(:ok)
      expect(parsed_response).to eq({})
    end

    it 'rejects a malformed (non-Hash) update response with a 502' do
      sign_in_as(user)
      allow(client).to receive(:update)
        .with('abc123', kvpid: 'kvp1', payload:, user_id: idp_user_id)
        .and_return([])

      expect { post '/v0/cave/abc123/update?kvpid=kvp1', params: payload.to_json, headers: json_headers }
        .to trigger_statsd_increment('api.cave.update.invalid_payload')

      expect(response).to have_http_status(:bad_gateway)
    end

    it 'keeps non-intake upstream 400 errors generic' do
      sign_in_as(user)
      allow(client).to receive(:update)
        .with('abc123', kvpid: 'kvp1', payload:, user_id: idp_user_id)
        .and_raise(
          idp_error(
            upstream_status: 400,
            upstream_body: { 'error' => 'DynamoDB exploded' },
            operation: 'update',
            failure_category: 'upstream_response'
          )
        )

      post '/v0/cave/abc123/update?kvpid=kvp1', params: payload.to_json, headers: json_headers

      expect(response).to have_http_status(:bad_gateway)
      expect(parsed_response['errors'].first).to include(
        'code' => 'idp_upstream_unavailable',
        'status' => '502',
        'detail' => 'Document processing service is temporarily unavailable'
      )
    end
  end

  describe 'POST /v0/cave/diff' do
    let(:json_headers) { { 'CONTENT_TYPE' => 'application/json' } }

    it 'returns 401 when unauthenticated' do
      post '/v0/cave/diff', params: { lhs: {}, rhs: {} }.to_json, headers: json_headers

      expect(response).to have_http_status(:unauthorized)
    end

    it 'requires a JSON object request body' do
      sign_in_as(user)

      post '/v0/cave/diff', params: '[]', headers: json_headers

      expect(response).to have_http_status(:bad_request)
    end

    it "requires both 'lhs' and 'rhs'" do
      sign_in_as(user)

      post '/v0/cave/diff', params: { lhs: {} }.to_json, headers: json_headers

      expect(response).to have_http_status(:bad_request)
    end

    it 'returns coarse and fine-grained differences' do
      sign_in_as(user)
      payload = {
        lhs: { first_name: 'jee', last_name: 'doe' },
        rhs: { first_name: 'john', last_name: 'doe' }
      }

      post '/v0/cave/diff', params: payload.to_json, headers: json_headers

      expect(response).to have_http_status(:ok)
      expect(parsed_response).to eq(
        'is_different' => true,
        'diff' => [
          { 'first_name' => { 'lhs' => 'jee', 'rhs' => 'john', 'is_different' => true } }
        ]
      )
    end

    it 'returns no differences when payloads are equal' do
      sign_in_as(user)
      payload = {
        lhs: { first_name: 'john', last_name: 'doe' },
        rhs: { first_name: 'john', last_name: 'doe' }
      }

      post '/v0/cave/diff', params: payload.to_json, headers: json_headers

      expect(response).to have_http_status(:ok)
      expect(parsed_response).to eq('is_different' => false, 'diff' => [])
    end
  end
end
