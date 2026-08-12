# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'V0::Appeals', type: :request do
  include SchemaMatchers

  appeals_endpoint = '/v0/appeals'

  before { sign_in_as(user) }

  context 'with a loa1 user' do
    let(:user) { create(:user, :loa1, ssn: '111223333') }

    it 'returns a forbidden error' do
      get appeals_endpoint
      expect(response).to have_http_status(:forbidden)
    end
  end

  context 'with a loa3 user without a ssn' do
    let(:user) { create(:user, :loa1, ssn: nil) }

    it 'returns a forbidden error' do
      get appeals_endpoint
      expect(response).to have_http_status(:forbidden)
    end
  end

  context 'with a loa3 user' do
    let(:user) { create(:user, :loa3, ssn: '111223333') }

    context 'with a valid response' do
      it 'returns a successful response' do
        VCR.use_cassette('caseflow/appeals') do
          get appeals_endpoint
          expect(response).to have_http_status(:ok)
          expect(response.body).to be_a(String)
          expect(response).to match_response_schema('appeals')
        end
      end

      it 'allows null issue descriptions' do
        VCR.use_cassette('caseflow/appeals') do
          get appeals_endpoint
          expect(response).to have_http_status(:ok)

          response_data = JSON.parse(response.body)
          # Add a null description to the first issue of the first appeal
          response_data['data'].first['attributes']['issues'].first['description'] = nil
          # Validate that the modified response still matches the schema
          expect(response_data).to match_schema('appeals')
        end
      end
    end

    context 'with a not authorized response' do
      it 'returns a 502 and logs an error level message' do
        VCR.use_cassette('caseflow/not_authorized') do
          get appeals_endpoint
          expect(response).to have_http_status(:bad_gateway)
          expect(response).to match_response_schema('errors')
        end
      end
    end

    context 'with a not found response' do
      it 'returns a 404 and logs an info level message' do
        VCR.use_cassette('caseflow/not_found') do
          get appeals_endpoint
          expect(response).to have_http_status(:not_found)
          expect(response).to match_response_schema('errors')
        end
      end
    end

    context 'with an unprocessible entity response' do
      it 'returns a 422 and logs an info level message' do
        VCR.use_cassette('caseflow/invalid_ssn') do
          get appeals_endpoint
          expect(response).to have_http_status(:unprocessable_entity)
          expect(response).to match_response_schema('errors')
        end
      end
    end

    context 'with a server error' do
      it 'returns a 502 and logs an error level message' do
        VCR.use_cassette('caseflow/server_error') do
          get appeals_endpoint
          expect(response).to have_http_status(:bad_gateway)
          expect(response).to match_response_schema('errors')
        end
      end
    end

    context 'with an invalid JSON body in the response' do
      it 'returns a 503 and logs an error level message' do
        VCR.use_cassette('caseflow/invalid_body') do
          get appeals_endpoint
          expect(response).to have_http_status(:service_unavailable)
        end
      end
    end

    context 'with a null eta' do
      it 'returns a successful response' do
        VCR.use_cassette('caseflow/appeals_null_eta') do
          get appeals_endpoint
          expect(response).to have_http_status(:ok)
          expect(response.body).to be_a(String)
          expect(response).to match_response_schema('appeals')
        end
      end
    end

    context 'with no alert details due_date' do
      it 'returns a successful response' do
        VCR.use_cassette('caseflow/appeals_no_alert_details_due_date') do
          get appeals_endpoint
          expect(response).to have_http_status(:ok)
          expect(response.body).to be_a(String)
          expect(response).to match_response_schema('appeals')
        end
      end
    end

    context 'with supplemental claim evidence submission enrichment' do
      let(:sc_id) { 'SC10879' }
      let(:sc_cassette) { 'caseflow/appeal_with_null_issue_description' }

      before do
        # Prevent noise from the null-issue-description handling in Caseflow::Service
        # (present in this cassette but not the focus of these tests).
        allow(StatsD).to receive(:increment)
        allow(Rails.logger).to receive(:warn)
        allow(PersonalInformationLog).to receive(:create!)

        allow(Flipper).to receive(:enabled?).and_call_original
      end

      context 'when cst_supplemental_claims_evidence_upload is disabled' do
        before do
          allow(Flipper).to receive(:enabled?)
            .with(:cst_supplemental_claims_evidence_upload, instance_of(User))
            .and_return(false)
        end

        it 'does not add evidenceSubmissions to any entry' do
          VCR.use_cassette(sc_cassette) { get appeals_endpoint }
          expect(response).to have_http_status(:ok)
          body = JSON.parse(response.body)
          body['data'].each do |entry|
            expect(entry['attributes']).not_to have_key('evidenceSubmissions')
          end
        end

        it 'does not issue an evidence_submissions SQL query' do
          query_count = evidence_submissions_query_count do
            VCR.use_cassette(sc_cassette) { get appeals_endpoint }
          end
          expect(query_count).to eq(0)
        end
      end

      context 'when cst_supplemental_claims_evidence_upload is enabled' do
        before do
          allow(Flipper).to receive(:enabled?)
            .with(:cst_supplemental_claims_evidence_upload, instance_of(User))
            .and_return(true)
        end

        context 'with a matching evidence submission row' do
          let!(:submission) do
            create(:cst_sc_evidence_submission, caseflow_claim_id: sc_id, user_account: user.user_account)
          end

          it 'attaches evidenceSubmissions to the matching SC entry' do
            VCR.use_cassette(sc_cassette) { get appeals_endpoint }
            body = JSON.parse(response.body)
            sc_entry = body['data'].find { |e| e['id'] == sc_id }
            submissions = sc_entry['attributes']['evidenceSubmissions']
            expect(submissions.size).to eq(1)
            expect(submissions.first).to include(
              'id' => submission.id.to_s,
              'fileName' => 'doctors-note.pdf',
              'documentType' => 'Correspondence',
              'uploadStatus' => 'SUCCESS'
            )
            expect(submissions.first['createdAt']).to be_present
          end

          it 'attaches an empty array to SC entries without matching rows' do
            VCR.use_cassette(sc_cassette) { get appeals_endpoint }
            body = JSON.parse(response.body)
            other_sc = body['data'].find { |e| e['type'] == 'supplementalClaim' && e['id'] != sc_id }
            expect(other_sc['attributes']['evidenceSubmissions']).to eq([])
          end

          it 'leaves non-SC entries unchanged' do
            VCR.use_cassette(sc_cassette) { get appeals_endpoint }
            body = JSON.parse(response.body)
            body['data'].reject { |e| e['type'] == 'supplementalClaim' }.each do |entry|
              expect(entry['attributes']).not_to have_key('evidenceSubmissions')
            end
          end

          it 'issues exactly one evidence_submissions query regardless of SC count' do
            query_count = evidence_submissions_query_count do
              VCR.use_cassette(sc_cassette) { get appeals_endpoint }
            end
            expect(query_count).to eq(1)
          end
        end

        context 'without any matching rows' do
          it 'attaches empty arrays to SC entries and leaves others unchanged' do
            VCR.use_cassette(sc_cassette) { get appeals_endpoint }
            body = JSON.parse(response.body)
            scs = body['data'].select { |e| e['type'] == 'supplementalClaim' }
            expect(scs).not_to be_empty
            scs.each { |sc| expect(sc['attributes']['evidenceSubmissions']).to eq([]) }
          end
        end

        context 'when a supplemental claim entry has missing attributes' do
          let(:appeals_payload) do
            {
              'data' => [
                {
                  'id' => sc_id,
                  'type' => 'supplementalClaim'
                },
                {
                  'id' => 'HLR123',
                  'type' => 'higherLevelReview',
                  'attributes' => {}
                }
              ]
            }
          end

          before do
            response_double = instance_double(Faraday::Response, body: appeals_payload)
            allow_any_instance_of(Caseflow::Service)
              .to receive(:get_appeals)
              .with(instance_of(User))
              .and_return(response_double)
          end

          it 'does not raise and adds evidenceSubmissions under attributes' do
            get appeals_endpoint

            expect(response).to have_http_status(:ok)
            body = JSON.parse(response.body)
            sc_entry = body['data'].find { |e| e['id'] == sc_id }

            expect(sc_entry['attributes']).to include('evidenceSubmissions' => [])
          end
        end

        context 'with rows belonging to a different veteran' do
          let(:other_user) { create(:user, :loa3) }

          before do
            create(:cst_sc_evidence_submission,
                   caseflow_claim_id: sc_id,
                   user_account: other_user.user_account,
                   file_name: 'other-veteran.pdf')
          end

          it "does not leak the other veteran's uploads" do
            VCR.use_cassette(sc_cassette) { get appeals_endpoint }
            body = JSON.parse(response.body)
            sc_entry = body['data'].find { |e| e['id'] == sc_id }
            expect(sc_entry['attributes']['evidenceSubmissions']).to eq([])
          end
        end
      end

      def evidence_submissions_query_count(&)
        count = 0
        callback = lambda do |_name, _start, _finish, _id, payload|
          count += 1 if payload[:sql].to_s.include?('evidence_submissions')
        end
        ActiveSupport::Notifications.subscribed(callback, 'sql.active_record', &)
        count
      end
    end
  end
end
