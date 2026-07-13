# frozen_string_literal: true

require 'rails_helper'
require_relative '../../rails_helper'
require 'bgs/power_of_attorney_verifier'
require 'bgs_service/e_benefits_bnft_claim_status_web_service'

RSpec.describe 'ClaimsApi::V1::Claims', type: :request do
  include SchemaMatchers

  let(:request_headers) do
    {
      'X-VA-SSN' => '796-04-3735',
      'X-VA-First-Name' => 'WESLEY',
      'X-VA-Last-Name' => 'FORD',
      'X-VA-Birth-Date' => '1986-05-06T00:00:00+00:00'
    }
  end
  let(:camel_inflection_header) { { 'X-Key-Inflection' => 'camel' } }
  let(:request_headers_camel) { request_headers.merge(camel_inflection_header) }
  let(:scopes) { %w[claim.read] }
  let(:target_veteran) do
    OpenStruct.new(
      icn: '1012832025V743496',
      first_name: 'Wesley',
      last_name: 'Ford',
      loa: { current: 3, highest: 3 },
      edipi: '1007697216',
      ssn: '796043735',
      participant_id: '600061742',
      mpi: OpenStruct.new(
        icn: '1012832025V743496',
        profile: OpenStruct.new(ssn: '796043735')
      )
    )
  end
  let(:claims_service) do
    if Flipper.enabled? :claims_status_v1_bgs_enabled
      ClaimsApi::EbenefitsBnftClaimStatusWebService
    else
      ClaimsApi::UnsynchronizedEVSSClaimService
    end
  end
  let(:bgs_claim_id) { '600118851' }

  before do
    stub_poa_verification
    # Stub participant validation for legacy request specs that use VCR cassettes with
    # participant IDs that may not match the test veteran.
    allow_any_instance_of(ClaimsApi::V1::ClaimsController)
      .to receive(:validate_bgs_participant!).and_return(nil)
  end

  context 'index' do
    it 'lists all Claims', run_at: 'Tue, 12 Dec 2017 03:09:06 GMT' do
      mock_acg(scopes) do |auth_header|
        VCR.use_cassette('claims_api/bgs/claims/claims') do
          allow_any_instance_of(ClaimsApi::V1::ApplicationController)
            .to receive(:target_veteran).and_return(target_veteran)
          get '/services/claims/v1/claims', params: nil, headers: request_headers.merge(auth_header)
          expect(response).to match_response_schema('claims_api/claims')
        end
      end
    end

    it 'lists all Claims when camel-inflection', run_at: 'Tue, 12 Dec 2017 03:09:06 GMT' do
      mock_acg(scopes) do |auth_header|
        VCR.use_cassette('claims_api/bgs/claims/claims') do
          allow_any_instance_of(ClaimsApi::V1::ApplicationController)
            .to receive(:target_veteran).and_return(target_veteran)
          get '/services/claims/v1/claims', params: nil, headers: request_headers_camel.merge(auth_header)
          expect(response).to match_camelized_response_schema('claims_api/claims')
        end
      end
    end

    context 'with errors' do
      it 'shows a errored Claims not found error message' do
        mock_acg(scopes) do |auth_header|
          VCR.use_cassette('claims_api/bgs/claims/claims_with_errors') do
            get '/services/claims/v1/claims', params: nil, headers: request_headers.merge(auth_header)
            expect(response).to have_http_status(:not_found)
          end
        end
      end
    end
  end

  describe 'SHOW endpoint validates user request access against ICN and BGS' do
    let(:veteran_id) { '1012667169V030190' }
    let(:bgs_claim_response) { build(:bgs_response_with_one_lc_status).to_h }
    let(:bnft_claim_web_service) { ClaimsApi::EbenefitsBnftClaimStatusWebService }
    let(:evss_id) { '111111111' }
    let(:veteran_participant_id) { '600045025' }
    let(:evss_claim_data) do
      {
        'date' => '11/06/2018',
        'max_est_claim_date' => '11/06/2019',
        'claim_complete_date' => nil,
        'waiver5103_submitted' => false,
        'attention_needed' => 'No',
        'development_letter_sent' => 'No',
        'decision_notification_sent' => 'No',
        'status_type' => 'Compensation',
        'poa' => 'Disabled American Veterans',
        'contention_list' => [],
        'claim_tracked_items' => {},
        'vba_document_list' => [],
        'claim_phase_dates' => {
          'latest_phase_type' => 'Claim received'
        }
      }
    end

    before do
      allow_any_instance_of(ClaimsApi::V1::ClaimsController)
        .to receive(:validate_bgs_participant!).and_call_original
    end

    def mock_target_veteran(icn, participant_id, ssn: '796043735')
      OpenStruct.new(
        icn:,
        first_name: 'Wesley',
        last_name: 'Ford',
        loa: { current: 3, highest: 3 },
        edipi: '1007697216',
        ssn:,
        participant_id:,
        mpi: OpenStruct.new(
          icn:,
          profile: OpenStruct.new(ssn:)
        )
      )
    end

    def stub_evss_service_response
      bgs_claim = {
        benefit_claim_details_dto: {
          bnft_claim_id: evss_id,
          ptcpnt_vet_id: veteran_participant_id,
          ptcpnt_clmant_id: veteran_participant_id
        }
      }
      allow_any_instance_of(bnft_claim_web_service)
        .to receive(:find_benefit_claim_details_by_benefit_claim_id)
        .and_return(bgs_claim)
      allow_any_instance_of(bnft_claim_web_service)
        .to receive(:transform_bgs_claim_to_evss)
        .and_return(ClaimsApi::EVSSClaim.new(evss_id:, data: evss_claim_data))
    end

    def make_claim_request(headers, claim_id: bgs_claim_id)
      get "/services/claims/v1/claims/#{claim_id}", params: { id: claim_id }, headers:
    end

    describe 'using a lighthouse claim id' do
      let(:lh_claim) do
        create(
          :auto_established_claim,
          status: 'PENDING',
          veteran_icn: veteran_id,
          evss_id: nil
        )
      end

      context 'User is a veteran trying to access their claim information with a lighthouse claim id' do
        it 'validates successfully and returns the claim information', run_at: 'Wed, 13 Dec 2017 03:28:23 GMT' do
          mock_acg(scopes) do |auth_header|
            VCR.use_cassette('claims_api/bgs/tracked_items/find_tracked_items') do
              VCR.use_cassette('claims_api/evss/documents/get_claim_documents') do
                allow_any_instance_of(ClaimsApi::V1::ApplicationController)
                  .to receive(:target_veteran).and_return(mock_target_veteran(veteran_id, veteran_participant_id))

                expect(ClaimsApi::AutoEstablishedClaim)
                  .to receive(:get_by_id_and_icn).and_return(lh_claim)

                make_claim_request(auth_header, claim_id: lh_claim.id)

                json_response = JSON.parse(response.body)
                expect(response).to have_http_status(:ok)
                expect(json_response.keys).to include('data')
                expect(json_response['data']['id']).to eq(lh_claim.id)
              end
            end
          end
        end
      end

      context 'User is a veteran attempting to access a claim that does not belong to them' do
        it 'raises a not found error', run_at: 'Wed, 13 Dec 2017 03:28:23 GMT' do
          mock_acg(scopes) do |auth_header|
            VCR.use_cassette('claims_api/bgs/tracked_items/find_tracked_items') do
              VCR.use_cassette('claims_api/evss/documents/get_claim_documents') do
                allow_any_instance_of(ClaimsApi::V1::ClaimsController)
                  .to receive(:target_veteran).and_return(mock_target_veteran('some-other-icn', veteran_participant_id))

                make_claim_request(auth_header, claim_id: lh_claim.id)

                expect(response).to have_http_status(:not_found)
                expect(JSON.parse(response.body)['errors'][0]['detail']).to eq('Claim not found')
              end
            end
          end
        end
      end

      context "POA accessing a veteran's claim with header request" do
        it 'validates successfully and returns the claim information', run_at: 'Wed, 13 Dec 2017 03:28:23 GMT' do
          mock_acg(scopes) do |auth_header|
            VCR.use_cassette('claims_api/bgs/tracked_items/find_tracked_items') do
              VCR.use_cassette('claims_api/evss/documents/get_claim_documents') do
                # target_veteran represents the veteran the POA is acting on behalf of
                allow_any_instance_of(ClaimsApi::V1::ApplicationController)
                  .to receive(:target_veteran).and_return(mock_target_veteran(veteran_id, veteran_participant_id))

                expect(ClaimsApi::AutoEstablishedClaim)
                  .to receive(:get_by_id_and_icn).and_return(lh_claim)

                header_request_headers = request_headers.merge(auth_header).merge(
                  {
                    'X-VA-First-Name' => 'POA',
                    'X-VA-Last-Name' => 'Representative',
                    'X-VA-SSN' => '111223333'
                  }
                )

                make_claim_request(header_request_headers, claim_id: lh_claim.id)

                json_response = JSON.parse(response.body)
                expect(response).to have_http_status(:ok)
                expect(json_response.keys).to include('data')
                expect(json_response['data']['id']).to eq(lh_claim.id)
              end
            end
          end
        end
      end
    end

    describe 'using an evss_id when no lighthouse claim is found' do
      # currently coupled to this feature flag, and can be updated once the feature flag is removed
      before do
        allow_any_instance_of(Flipper).to receive(:enabled?).with(:claims_status_v1_bgs_enabled).and_return(true)
        # No lighthouse claim exists for this ID — controller falls through to the numeric BGS branch
        allow(ClaimsApi::AutoEstablishedClaim).to receive(:get_by_id_and_icn).and_return(nil)
      end

      context 'User is a veteran trying to access their claim information with an evss_id' do
        it 'validates successfully and returns the claim information', run_at: 'Wed, 13 Dec 2017 03:28:23 GMT' do
          mock_acg(scopes) do |auth_header|
            VCR.use_cassette('claims_api/bgs/tracked_items/find_tracked_items') do
              VCR.use_cassette('claims_api/evss/documents/get_claim_documents') do
                allow_any_instance_of(ClaimsApi::V1::ClaimsController)
                  .to receive(:target_veteran).and_return(mock_target_veteran(veteran_id, veteran_participant_id))

                stub_evss_service_response

                make_claim_request(auth_header, claim_id: evss_id)

                json_response = JSON.parse(response.body)
                expect(response).to have_http_status(:ok)
                expect(json_response.keys).to include('data')
                expect(json_response['data']['id']).to eq(evss_id)
                expect(response).to match_response_schema('claims_api/claim')
              end
            end
          end
        end
      end

      context 'User is a veteran attempting to access a claim that does not belong to them' do
        before do
          allow_any_instance_of(ClaimsApi::V1::ClaimsController)
            .to receive(:validate_bgs_participant!)
            .and_raise(
              Common::Exceptions::ResourceNotFound.new(detail: ClaimsApi::V1::ClaimsController::INVALID_CLAIM_ACCESS_DETAIL)
            )
        end

        it 'raises a not found error', run_at: 'Wed, 13 Dec 2017 03:28:23 GMT' do
          mock_acg(scopes) do |auth_header|
            allow_any_instance_of(ClaimsApi::V1::ClaimsController)
              .to receive(:target_veteran).and_return(mock_target_veteran(veteran_id, veteran_participant_id))
            # Claim belongs to a different participant — validation should reject the request
            allow_any_instance_of(bnft_claim_web_service)
              .to receive(:find_benefit_claim_details_by_benefit_claim_id)
              .and_return(
                {
                  benefit_claim_details_dto: {
                    ptcpnt_vet_id: 'some-other-participant-id',
                    ptcpnt_clmant_id: 'some-other-participant-id'
                  }
                }
              )
            allow_any_instance_of(bnft_claim_web_service)
              .to receive(:transform_bgs_claim_to_evss)
              .and_return(ClaimsApi::EVSSClaim.new(evss_id:, data: evss_claim_data))

            make_claim_request(auth_header, claim_id: evss_id)

            expect(response).to have_http_status(:not_found)
            expect(JSON.parse(response.body)['errors'][0]['detail']).to eq('Claim not found')
          end
        end
      end

      context "POA accessing a veteran's claim with header request" do
        it 'validates successfully and returns the claim information', run_at: 'Wed, 13 Dec 2017 03:28:23 GMT' do
          mock_acg(scopes) do |auth_header|
            VCR.use_cassette('claims_api/bgs/tracked_items/find_tracked_items') do
              VCR.use_cassette('claims_api/evss/documents/get_claim_documents') do
                # target_veteran represents the veteran the POA is acting on behalf of
                allow_any_instance_of(ClaimsApi::V1::ApplicationController)
                  .to receive(:target_veteran).and_return(mock_target_veteran(veteran_id, veteran_participant_id))

                # BGS claim participant IDs match the veteran — validation should pass
                stub_evss_service_response

                header_request_headers = request_headers.merge(auth_header).merge(
                  {
                    'X-VA-First-Name' => 'POA',
                    'X-VA-Last-Name' => 'Representative',
                    'X-VA-SSN' => '111223333'
                  }
                )

                make_claim_request(header_request_headers, claim_id: evss_id)

                json_response = JSON.parse(response.body)
                expect(response).to have_http_status(:ok)
                expect(json_response.keys).to include('data')
                expect(json_response['data']['id']).to eq(evss_id)
                expect(response).to match_response_schema('claims_api/claim')
              end
            end
          end
        end
      end
    end

    context "The BGS claim ptcpnt_vet_id or ptcpnt_clmant_id does not match the veteran's participant ID" do
      before do
        allow_any_instance_of(Flipper).to receive(:enabled?).with(:claims_status_v1_bgs_enabled).and_return(true)
        allow(ClaimsApi::AutoEstablishedClaim).to receive(:get_by_id_and_icn).and_return(nil)
        allow_any_instance_of(ClaimsApi::V1::ClaimsController)
          .to receive(:validate_bgs_participant!)
          .and_raise(
            Common::Exceptions::ResourceNotFound.new(detail: ClaimsApi::V1::ClaimsController::INVALID_CLAIM_ACCESS_DETAIL)
          )
      end

      it 'raises a not found error', run_at: 'Wed, 13 Dec 2017 03:28:23 GMT' do
        mock_acg(scopes) do |auth_header|
          allow_any_instance_of(ClaimsApi::V1::ClaimsController)
            .to receive(:target_veteran).and_return(mock_target_veteran(veteran_id, veteran_participant_id))
          allow_any_instance_of(bnft_claim_web_service)
            .to receive(:find_benefit_claim_details_by_benefit_claim_id)
            .and_return(
              {
                benefit_claim_details_dto: {
                  ptcpnt_vet_id: 'some-other-participant-id',
                  ptcpnt_clmant_id: 'some-other-participant-id'
                }
              }
            )
          allow_any_instance_of(bnft_claim_web_service)
            .to receive(:transform_bgs_claim_to_evss)
            .and_return(ClaimsApi::EVSSClaim.new(evss_id:, data: evss_claim_data))

          make_claim_request(auth_header)

          expect(response).to have_http_status(:not_found)
          expect(JSON.parse(response.body)['errors'][0]['detail'])
            .to eq('Claim not found')
        end
      end
    end
  end

  context 'for a single claim' do
    it 'shows a single Claim', run_at: 'Wed, 13 Dec 2017 03:28:23 GMT' do
      mock_acg(scopes) do |auth_header|
        VCR.use_cassette('claims_api/bgs/claims/claim') do
          get "/services/claims/v1/claims/#{bgs_claim_id}", params: nil, headers: request_headers.merge(auth_header)
          expect(response).to match_response_schema('claims_api/claim')
        end
      end
    end

    it 'shows a single Claim when camel-inflected', run_at: 'Wed, 13 Dec 2017 03:28:23 GMT' do
      mock_acg(scopes) do |auth_header|
        VCR.use_cassette('claims_api/bgs/claims/claim') do
          get "/services/claims/v1/claims/#{bgs_claim_id}", params: nil,
                                                            headers: request_headers_camel.merge(auth_header)
          expect(response).to match_camelized_response_schema('claims_api/claim')
        end
      end
    end

    context 'when source matches' do
      context 'when evss_id is provided' do
        it 'shows a single Claim through auto established claims', run_at: 'Wed, 13 Dec 2017 03:28:23 GMT' do
          mock_acg(scopes) do |auth_header|
            create(:auto_established_claim,
                   status: 'pending',
                   source: 'abraham lincoln',
                   auth_headers: { some: 'data' },
                   evss_id: 600_118_851,
                   veteran_icn: '1013062086V794840',
                   id: 'd5536c5c-0465-4038-a368-1a9d9daf65c9')
            VCR.use_cassette('claims_api/bgs/claims/claim') do
              get(
                "/services/claims/v1/claims/#{bgs_claim_id}",
                params: nil, headers: request_headers.merge(auth_header)
              )
              expect(response).to match_response_schema('claims_api/claim')
              expect(JSON.parse(response.body)['data']['id']).to eq('d5536c5c-0465-4038-a368-1a9d9daf65c9')
            end
          end
        end

        it 'shows a single Claim through auto established claims when camel-inflected',
           run_at: 'Wed, 13 Dec 2017 03:28:23 GMT' do
          mock_acg(scopes) do |auth_header|
            create(:auto_established_claim,
                   status: 'pending',
                   source: 'abraham lincoln',
                   auth_headers: { some: 'data' },
                   evss_id: 600_118_851,
                   veteran_icn: '1013062086V794840',
                   id: 'd5536c5c-0465-4038-a368-1a9d9daf65c9')
            VCR.use_cassette('claims_api/bgs/claims/claim') do
              get(
                "/services/claims/v1/claims/#{bgs_claim_id}",
                params: nil, headers: request_headers_camel.merge(auth_header)
              )
              expect(response).to match_camelized_response_schema('claims_api/claim')
              expect(JSON.parse(response.body)['data']['id']).to eq('d5536c5c-0465-4038-a368-1a9d9daf65c9')
            end
          end
        end
      end

      context 'when uuid is provided' do
        it 'shows a single Claim through auto established claims', run_at: 'Wed, 13 Dec 2017 03:28:23 GMT' do
          mock_acg(scopes) do |auth_header|
            create(:auto_established_claim,
                   status: 'pending',
                   source: 'abraham lincoln',
                   auth_headers: { some: 'data' },
                   evss_id: 600_118_851,
                   veteran_icn: '1013062086V794840',
                   id: 'd5536c5c-0465-4038-a368-1a9d9daf65c9')
            VCR.use_cassette('claims_api/bgs/claims/claim') do
              get(
                '/services/claims/v1/claims/d5536c5c-0465-4038-a368-1a9d9daf65c9',
                params: nil, headers: request_headers.merge(auth_header)
              )
              expect(response).to match_response_schema('claims_api/claim')
              expect(JSON.parse(response.body)['data']['id']).to eq('d5536c5c-0465-4038-a368-1a9d9daf65c9')
            end
          end
        end
      end
    end

    context 'when source does not match' do
      it 'shows a single Claim through auto established claims', run_at: 'Wed, 13 Dec 2017 03:28:23 GMT' do
        mock_acg(scopes) do |auth_header|
          create(:auto_established_claim,
                 status: 'pending',
                 source: 'oddball',
                 auth_headers: { some: 'data' },
                 evss_id: 600_118_851,
                 veteran_icn: '1013062086V794840',
                 id: 'd5536c5c-0465-4038-a368-1a9d9daf65c9')
          expect_any_instance_of(claims_service).to receive(:update_from_remote)
            .and_raise(StandardError.new('no claim found'))
          VCR.use_cassette('claims_api/bgs/claims/claim') do
            get(
              "/services/claims/v1/claims/#{bgs_claim_id}",
              params: nil, headers: request_headers.merge(auth_header)
            )
            expect(response.code.to_i).to eq(404)
          end
        end
      end
    end

    context 'with errors' do
      it '404s' do
        mock_acg(scopes) do |auth_header|
          VCR.use_cassette('claims_api/bgs/claims/claim_with_errors') do
            get '/services/claims/v1/claims/123123131', params: nil, headers: request_headers.merge(auth_header)
            expect(response).to have_http_status(:not_found)
          end
        end
      end

      it 'missing MPI Record' do
        mock_acg(scopes) do |auth_header|
          VCR.use_cassette('claims_api/bgs/claims/claim_with_errors') do
            vet = ClaimsApi::Veteran.new(
              uuid: request_headers['X-VA-SSN']&.gsub(/[^0-9]/, ''),
              ssn: request_headers['X-VA-SSN']&.gsub(/[^0-9]/, ''),
              first_name: request_headers['X-VA-First-Name'],
              last_name: request_headers['X-VA-Last-Name'],
              va_profile: ClaimsApi::Veteran.build_profile(request_headers['X-VA-Birth-Date']),
              last_signed_in: Time.now.utc
            )
            vet.participant_id = nil
            allow_any_instance_of(ClaimsApi::V1::ApplicationController)
              .to receive(:veteran_from_headers).and_return(vet)

            allow_any_instance_of(ClaimsApi::Veteran)
              .to receive(:mpi_record?).and_return(false)

            get '/services/claims/v1/claims/123123131', params: nil, headers: request_headers.merge(auth_header)

            expect(response).to have_http_status(:unprocessable_content)
            body = JSON.parse(response.body)
            expect(body['errors'][0]['detail']).to eq('Unable to locate Veteran in Master Person Index (MPI). ' \
                                                      'Please submit an issue at ask.va.gov or call ' \
                                                      '1-800-MyVA411 (800-698-2411) for assistance.')
          end
        end
      end

      it 'missing an ICN' do
        mock_acg(scopes) do |auth_header|
          VCR.use_cassette('claims_api/bgs/claims/claim_with_errors') do
            vet = ClaimsApi::Veteran.new(
              uuid: request_headers['X-VA-SSN']&.gsub(/[^0-9]/, ''),
              ssn: request_headers['X-VA-SSN']&.gsub(/[^0-9]/, ''),
              first_name: request_headers['X-VA-First-Name'],
              last_name: request_headers['X-VA-Last-Name'],
              va_profile: ClaimsApi::Veteran.build_profile(request_headers['X-VA-Birth-Date']),
              last_signed_in: Time.now.utc
            )
            vet.icn = nil
            allow_any_instance_of(ClaimsApi::V1::ApplicationController)
              .to receive(:veteran_from_headers).and_return(vet)

            get '/services/claims/v1/claims/123123131', params: nil, headers: request_headers.merge(auth_header)

            expect(response).to have_http_status(:unprocessable_content)
            body = JSON.parse(response.body)
            expect(body['errors'][0]['detail']).to eq('Veteran missing Integration Control Number (ICN). ' \
                                                      'Please submit an issue at ask.va.gov or call 1-800-MyVA411 ' \
                                                      '(800-698-2411) for assistance.')
          end
        end
      end

      it 'shows a single errored Claim with an error message', run_at: 'Wed, 13 Dec 2017 03:28:23 GMT' do
        mock_acg(scopes) do |auth_header|
          create(:auto_established_claim,
                 source: 'abraham lincoln',
                 auth_headers: auth_header,
                 evss_id: 600_118_851,
                 veteran_icn: '1013062086V794840',
                 id: 'd5536c5c-0465-4038-a368-1a9d9daf65c9',
                 status: 'errored',
                 evss_response: [{ 'key' => 'Error', 'severity' => 'FATAL', 'text' => 'Failed' }])
          VCR.use_cassette('claims_api/bgs/claims/claim') do
            headers = request_headers.merge(auth_header)
            get('/services/claims/v1/claims/d5536c5c-0465-4038-a368-1a9d9daf65c9', params: nil, headers:)
            expect(response).to have_http_status(:unprocessable_content)
          end
        end
      end

      it 'shows a single errored Claim without an error message', run_at: 'Wed, 13 Dec 2017 03:28:23 GMT' do
        mock_acg(scopes) do |auth_header|
          create(:auto_established_claim,
                 source: 'abraham lincoln',
                 auth_headers: auth_header,
                 evss_id: 600_118_851,
                 veteran_icn: '1013062086V794840',
                 id: 'd5536c5c-0465-4038-a368-1a9d9daf65c9',
                 status: 'errored',
                 evss_response: nil)
          VCR.use_cassette('claims_api/bgs/claims/claim') do
            headers = request_headers.merge(auth_header)
            get('/services/claims/v1/claims/d5536c5c-0465-4038-a368-1a9d9daf65c9', params: nil, headers:)
            expect(response).to have_http_status(:unprocessable_content)
          end
        end
      end

      context 'when looking up an errored claim by evss_id' do
        it 'finds the claim and returns errors', run_at: 'Wed, 13 Dec 2017 03:28:23 GMT' do
          mock_acg(scopes) do |auth_header|
            create(:auto_established_claim,
                   source: 'abraham lincoln',
                   auth_headers: auth_header,
                   evss_id: 600_118_851,
                   veteran_icn: '1013062086V794840',
                   id: 'd5536c5c-0465-4038-a368-1a9d9daf65c9',
                   status: 'errored',
                   evss_response: [{ 'key' => 'Error', 'severity' => 'FATAL', 'text' => 'BD upload failed' }])
            VCR.use_cassette('claims_api/bgs/claims/claim') do
              headers = request_headers.merge(auth_header)
              get("/services/claims/v1/claims/#{bgs_claim_id}", params: nil, headers:)
              expect(response).to have_http_status(:unprocessable_content)
              body = JSON.parse(response.body)
              expect(body['errors'].first['detail']).to include('BD upload failed')
            end
          end
        end
      end
    end
  end

  context 'POA verifier' do
    it 'users the poa verifier when the header is present' do
      mock_acg(scopes) do |auth_header|
        VCR.use_cassette('claims_api/bgs/claims/claim') do
          verifier_stub = instance_double(BGS::PowerOfAttorneyVerifier)
          allow(BGS::PowerOfAttorneyVerifier).to receive(:new) { verifier_stub }
          allow(verifier_stub).to receive(:verify)
          headers = request_headers.merge(auth_header)
          get("/services/claims/v1/claims/#{bgs_claim_id}", params: nil, headers:)
          expect(response).to have_http_status(:ok)
        end
      end
    end
  end

  context 'with oauth user and no headers' do
    it 'lists all Claims', run_at: 'Tue, 12 Dec 2017 03:09:06 GMT' do
      mock_acg(scopes) do |auth_header|
        verifier_stub = instance_double(BGS::PowerOfAttorneyVerifier)
        allow(BGS::PowerOfAttorneyVerifier).to receive(:new) { verifier_stub }
        allow(verifier_stub).to receive(:verify)
        VCR.use_cassette('claims_api/bgs/claims/claims') do
          allow_any_instance_of(ClaimsApi::V1::ApplicationController)
            .to receive(:target_veteran).and_return(target_veteran)
          get '/services/claims/v1/claims', params: nil, headers: auth_header
          expect(response).to match_response_schema('claims_api/claims')
        end
      end
    end

    it 'lists all Claims when camel-inflected', run_at: 'Tue, 12 Dec 2017 03:09:06 GMT' do
      mock_acg(scopes) do |auth_header|
        verifier_stub = instance_double(BGS::PowerOfAttorneyVerifier)
        allow(BGS::PowerOfAttorneyVerifier).to receive(:new) { verifier_stub }
        allow(verifier_stub).to receive(:verify)
        VCR.use_cassette('claims_api/bgs/claims/claims') do
          get '/services/claims/v1/claims', params: nil, headers: auth_header.merge(camel_inflection_header)
          expect(response).to match_camelized_response_schema('claims_api/claims')
        end
      end
    end
  end

  context "when a 'Token Validation Error' is received" do
    it "raises a 'Common::Exceptions::Unauthorized' exception", run_at: 'Tue, 12 Dec 2017 03:09:06 GMT' do
      auth = { Authorization: 'Bearer The-quick-brown-fox-jumped-over-the-lazy-dog' }
      VCR.use_cassette('claims_api/bgs/claims/claims') do
        get '/services/claims/v1/claims', params: nil,
                                          headers: request_headers.merge(auth)
        parsed_response = JSON.parse(response.body)

        expect(response).to have_http_status(:unauthorized)
        expect(parsed_response['errors'].first['title']).to eq('Not authorized')
      end
    end
  end

  context 'events timeline' do
    it 'maps BGS data to match previous logic with EVSS data' do
      mock_acg(scopes) do |auth_header|
        VCR.use_cassette('claims_api/bgs/claims/claim') do
          get "/services/claims/v1/claims/#{bgs_claim_id}", params: nil, headers: request_headers.merge(auth_header)
          body = JSON.parse(response.body)
          events_timeline = body['data']['attributes']['events_timeline']
          expect(response).to have_http_status(:ok)
          expect(events_timeline[1]['type']).to eq('completed')
          expect(events_timeline[2]['type']).to eq('filed')
        end
      end
    end
  end

  # possible to have errors saved in production that were saved with this wrapper
  # so need to make sure they do not break the formatter, even though the
  # key of 400 will still show as the source, it will return the claim instead of saying 'not found'
  context 'when a claim has an evss_response message with a key that is an integer' do
    let(:err_message) do
      [{
        'key' => 400,
        'severity' => 'FATAL',
        'text' =>
        { 'messages' =>
          [{
            'key' => 'form526.submit.establishClaim.serviceError',
            'severity' => 'FATAL',
            'text' => 'Claim not established. System error with BGS. GUID: 00797c5d-89d4-4da6-aab7-24b4ad0e4a4f'
          }] }
      }]
    end

    it 'shows correct error message despite the key being an integer' do
      mock_acg(scopes) do |auth_header|
        create(:auto_established_claim,
               source: 'abraham lincoln',
               auth_headers: auth_header,
               evss_id: 600_118_851,
               veteran_icn: '1013062086V794840',
               id: 'd5536c5c-0465-4038-a368-1a9d9daf65c9',
               status: 'errored',
               evss_response: err_message)
        VCR.use_cassette('bgs/claims/claim') do
          headers = request_headers.merge(auth_header)
          get('/services/claims/v1/claims/d5536c5c-0465-4038-a368-1a9d9daf65c9', params: nil, headers:)
          expect(response).not_to have_http_status(:not_found)
          body = JSON.parse(response.body)
          expect(body['errors'][0]['detail']).not_to eq('Claim not found')
          expect(body['errors'][0]['source']).to eq('400')
          expect(body['errors'][0]['detail']).to include('Claim not established')
        end
      end
    end
  end
end
