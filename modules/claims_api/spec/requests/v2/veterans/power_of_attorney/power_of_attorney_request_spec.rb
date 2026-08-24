# frozen_string_literal: true

require 'rails_helper'
require_relative '../../../../rails_helper'
require 'token_validation/v2/client'
require 'bgs_service/local_bgs'

RSpec.describe 'ClaimsApi::V2::PowerOfAttorney::PowerOfAttorneyRequest', type: :request do
  let(:veteran_id) { '1013062086V794840' }
  let(:request_path) { "/services/claims/v2/veterans/#{veteran_id}/power-of-attorney-request" }
  let(:scopes) { %w[system/claim.write system/claim.read] }
  let(:bgs_poa) { { person_org_name: "#{poa_code} name-here" } }
  let(:local_bgs) { ClaimsApi::LocalBGS }

  before do
    create(:veteran_representative, :vso, representative_id: '999999999999', poa_codes: ['067'])
    create(:veteran_organization, poa: '067', name: 'DISABLED AMERICAN VETERANS')
    allow(Flipper).to receive(:enabled?).with(:lighthouse_claims_api_poa_dependent_claimants).and_return(false)
  end

  context 'CCG (Client Credentials Grant) flow' do
    context 'when the token is valid' do
      context 'validation and value errors' do
        context 'when the Veteran ICN is not found in MPI' do
          it 'returns a meaningful 404' do
            mock_ccg(scopes) do |auth_header|
              allow_any_instance_of(ClaimsApi::V2::Veterans::PowerOfAttorney::RequestController)
                .to receive(:validate_country_code).and_return(nil)
              allow_any_instance_of(ClaimsApi::Veteran).to receive(:mpi_record?).and_return(false)

              detail = "Unable to locate Veteran's ID/ICN in Master Person Index (MPI). " \
                       'Please submit an issue at ask.va.gov or call 1-800-MyVA411 (800-698-2411) for assistance.'

              post request_path, params: { data: { attributes: nil } }.to_json, headers: auth_header

              response_body = JSON.parse(response.body)['errors'][0]

              expect(response).to have_http_status(:not_found)
              expect(response_body['title']).to eq('Resource not found')
              expect(response_body['status']).to eq('404')
              expect(response_body['detail']).to include(detail)
            end
          end
        end

        context 'when the request data is not a valid json object' do
          let(:data) { '123abc' }

          it 'returns a meaningful 422' do
            mock_ccg(scopes) do |auth_header|
              detail = 'The request body is not a valid JSON object: '

              post request_path, params: data, headers: auth_header

              response_body = JSON.parse(response.body)['errors'][0]

              expect(response).to have_http_status(:unprocessable_content)
              expect(response_body['title']).to eq('Unprocessable entity')
              expect(response_body['status']).to eq('422')
              expect(response_body['detail']).to include(detail)
            end
          end
        end

        context 'when the Veteran ICN is found in MPI' do
          context 'when request includes new optional disclosure and claimant fields' do
            let(:valid_request_hash) do
              JSON.parse(
                Rails.root.join('modules', 'claims_api', 'spec', 'fixtures', 'v2', 'veterans',
                                'power_of_attorney', 'request_representative', 'valid.json').read
              )
            end

            let(:user_profile) do
              double(
                'user_profile',
                status: :ok,
                profile: double(
                  'profile',
                  given_names: %w[Jane],
                  family_name: 'Doe',
                  participant_id: '123',
                  ssn: '123456789',
                  birth_date: Date.parse('1990-01-15'),
                  birls_id: '123456789'
                )
              )
            end

            before do
              allow_any_instance_of(ClaimsApi::V2::Veterans::PowerOfAttorney::BaseController)
                .to receive(:user_profile).and_return(user_profile)
              allow_any_instance_of(ClaimsApi::DependentClaimantVerificationService)
                .to receive(:validate_poa_code_exists!).and_return(nil)
              allow_any_instance_of(ClaimsApi::DependentClaimantVerificationService)
                .to receive(:validate_dependent_by_participant_id!).and_return(nil)
            end

            it 'allows individualNames without requiring consentDisclosureIndividuals' do
              request_hash = valid_request_hash.deep_dup
              request_hash['data']['attributes'].delete('consentDisclosureIndividuals')

              mock_ccg(scopes) do |auth_header|
                post request_path, params: request_hash.to_json, headers: auth_header

                expect(response).to have_http_status(:created)
              end
            end

            context 'when the claimant has duplicate participant IDs in MPI' do
              it_behaves_like 'returns 422 for claimant with duplicate participant IDs' do
                let(:submit_path) { request_path }
                let(:submit_scopes) { scopes }
                let(:submit_params) { valid_request_hash.to_json }
              end
            end
          end

          context 'when the request data does not pass schema validation' do
            let(:request_body) do
              Rails.root.join('modules', 'claims_api', 'spec', 'fixtures', 'v2', 'veterans',
                              'power_of_attorney', 'request_representative', 'invalid_schema.json').read
            end

            it 'returns a meaningful 422' do
              VCR.use_cassette('claims_api/mpi/find_candidate/valid_icn_full') do
                mock_ccg(scopes) do |auth_header|
                  detail = 'The property /representative did not contain the required key poaCode'

                  post request_path, params: request_body, headers: auth_header

                  response_body = JSON.parse(response.body)['errors'][0]

                  expect(response).to have_http_status(:unprocessable_content)
                  expect(response_body['title']).to eq('Unprocessable entity')
                  expect(response_body['status']).to eq('422')
                  expect(response_body['detail']).to include(detail)
                end
              end
            end
          end

          context 'when claimant dateOfBirth has an invalid format' do
            let(:request_body) do
              request_hash = JSON.parse(
                Rails.root.join('modules', 'claims_api', 'spec', 'fixtures', 'v2', 'veterans',
                                'power_of_attorney', 'request_representative', 'valid.json').read
              )
              request_hash['data']['attributes']['claimant']['dateOfBirth'] = '01-15-1990'
              request_hash.to_json
            end

            it 'returns a schema validation 422' do
              VCR.use_cassette('claims_api/mpi/find_candidate/valid_icn_full') do
                mock_ccg(scopes) do |auth_header|
                  post request_path, params: request_body, headers: auth_header

                  response_body = JSON.parse(response.body)['errors'][0]

                  expect(response).to have_http_status(:unprocessable_content)
                  expect(response_body['status']).to eq('422')
                  expect(response_body['detail']).to include('/claimant/dateOfBirth')
                end
              end
            end
          end

          context 'when individualNames contains a non-string item' do
            let(:request_body) do
              request_hash = JSON.parse(
                Rails.root.join('modules', 'claims_api', 'spec', 'fixtures', 'v2', 'veterans',
                                'power_of_attorney', 'request_representative', 'valid.json').read
              )
              request_hash['data']['attributes']['individualNames'] = ['jane', 123]
              request_hash.to_json
            end

            it 'returns a schema validation 422' do
              VCR.use_cassette('claims_api/mpi/find_candidate/valid_icn_full') do
                mock_ccg(scopes) do |auth_header|
                  post request_path, params: request_body, headers: auth_header

                  response_body = JSON.parse(response.body)['errors'][0]

                  expect(response).to have_http_status(:unprocessable_content)
                  expect(response_body['status']).to eq('422')
                  expect(response_body['detail']).to include('/individualNames/1')
                end
              end
            end
          end

          context 'when individualNames exceeds maxItems' do
            let(:request_body) do
              request_hash = JSON.parse(
                Rails.root.join('modules', 'claims_api', 'spec', 'fixtures', 'v2', 'veterans',
                                'power_of_attorney', 'request_representative', 'valid.json').read
              )
              request_hash['data']['attributes']['individualNames'] = Array.new(101, 'jane')
              request_hash.to_json
            end

            it 'returns a schema validation 422' do
              VCR.use_cassette('claims_api/mpi/find_candidate/valid_icn_full') do
                mock_ccg(scopes) do |auth_header|
                  post request_path, params: request_body, headers: auth_header

                  response_body = JSON.parse(response.body)['errors'][0]

                  expect(response).to have_http_status(:unprocessable_content)
                  expect(response_body['status']).to eq('422')
                  expect(response_body['detail']).to include('/individualNames')
                end
              end
            end
          end

          context 'when consentDisclosureAffiliated is not a boolean' do
            let(:request_body) do
              request_hash = JSON.parse(
                Rails.root.join('modules', 'claims_api', 'spec', 'fixtures', 'v2', 'veterans',
                                'power_of_attorney', 'request_representative', 'valid.json').read
              )
              request_hash['data']['attributes']['consentDisclosureAffiliated'] = 'true'
              request_hash.to_json
            end

            it 'returns a schema validation 422' do
              VCR.use_cassette('claims_api/mpi/find_candidate/valid_icn_full') do
                mock_ccg(scopes) do |auth_header|
                  post request_path, params: request_body, headers: auth_header

                  response_body = JSON.parse(response.body)['errors'][0]

                  expect(response).to have_http_status(:unprocessable_content)
                  expect(response_body['status']).to eq('422')
                  expect(response_body['detail']).to include('/consentDisclosureAffiliated')
                end
              end
            end
          end

          context 'when the claimant request data does not pass schema validation' do
            let(:request_body) do
              Rails.root.join('modules', 'claims_api', 'spec', 'fixtures', 'v2', 'veterans',
                              'power_of_attorney', 'request_representative', 'invalid_claimant_schema.json').read
            end

            it 'returns a meaningful 422' do
              VCR.use_cassette('claims_api/mpi/find_candidate/valid_icn_full') do
                mock_ccg(scopes) do |auth_header|
                  detail = "If claimant is present 'address' must be filled in with required fields addressLine1, " \
                           "city, stateCode and countryCode. If the countryCode is 'US' then zipCode is also required."

                  post request_path, params: request_body, headers: auth_header

                  response_body = JSON.parse(response.body)['errors'][0]

                  expect(response).to have_http_status(:unprocessable_content)
                  expect(response_body['title']).to eq('Unprocessable Entity')
                  expect(response_body['status']).to eq('422')
                  expect(response_body['detail']).to include(detail)
                end
              end
            end
          end
        end

        context 'when the request data passes schema validation' do
          context 'when no representative is found with the provided poaCode and registrationNumber' do
            let(:request_body) do
              Rails.root.join('modules', 'claims_api', 'spec', 'fixtures', 'v2', 'veterans',
                              'power_of_attorney', 'request_representative', 'invalid_poa.json').read
            end

            it 'returns a meaningful 404' do
              mock_ccg(scopes) do |auth_header|
                detail = 'Could not find an Accredited Representative with poa code: AG3'

                post request_path, params: request_body, headers: auth_header

                response_body = JSON.parse(response.body)['errors'][0]

                expect(response).to have_http_status(:not_found)
                expect(response_body['title']).to eq('Resource not found')
                expect(response_body['status']).to eq('404')
                expect(response_body['detail']).to include(detail)
              end
            end
          end
        end
      end

      context 'successful request' do
        let(:request_body) do
          Rails.root.join('modules', 'claims_api', 'spec', 'fixtures', 'v2', 'veterans',
                          'power_of_attorney', 'request_representative', 'valid.json').read
        end

        context 'lighthouse_claims_v2_poa_requests_skip_bgs disabled' do
          before do
            allow(Flipper).to receive(:enabled?).with(:lighthouse_claims_v2_poa_requests_skip_bgs).and_return(false)
          end

          let(:request_body) do
            Rails.root.join('modules', 'claims_api', 'spec', 'fixtures', 'v2', 'veterans',
                            'power_of_attorney', 'request_representative', 'valid_no_claimant.json').read
          end

          let(:orchestrator_res) do
            {
              'addressLine1' => '2719 Hyperion Ave', 'addressLine2' => 'Apt 2', 'addressLine3' => nil,
              'changeAddressAuth' => 'true', 'city' => 'Los Angeles', 'claimantPtcpntId' => '187216',
              'claimantRelationship' => nil, 'formTypeCode' => '21-22 ', 'insuranceNumbers' => '1234567890',
              'limitationAlcohol' => 'true', 'limitationDrugAbuse' => 'true', 'limitationHIV' => 'true',
              'limitationSCA' => 'true', 'organizationName' => '083 - DISABLED AMERICAN VETERANS',
              'otherServiceBranch' => nil, 'phoneNumber' => '5555551234', 'poaCode' => '083', 'postalCode' => '92264',
              'procId' => '3858517', 'representativeFirstName' => 'John', 'representativeLastName' => 'Doe',
              'representativeLawFirmOrAgencyName' => nil, 'representativeTitle' => 'MyJob',
              'representativeType' => 'Recognized Veterans Service Organization', 'section7332Auth' => 'true',
              'serviceBranch' => 'Army', 'serviceNumber' => '123678453', 'state' => 'CA', 'vdcStatus' => 'Submitted',
              'veteranPtcpntId' => '187216', 'acceptedBy' => nil, 'claimantFirstName' => 'JESSE',
              'claimantLastName' => 'GRAY', 'claimantMiddleName' => nil, 'declinedBy' => nil, 'declinedReason' => nil,
              'secondaryStatus' => nil, 'veteranFirstName' => 'JESSE', 'veteranLastName' => 'GRAY',
              'veteranMiddleName' => nil, 'veteranSSN' => '796378881', 'veteranVAFileNumber' => '796378881'
            }
          end

          it 'returns the expected response from the blueprinter' do
            mock_ccg(scopes) do |auth_header|
              allow_any_instance_of(ClaimsApi::PowerOfAttorneyRequestService::Orchestrator)
                .to receive(:submit_request).and_return(orchestrator_res)

              post request_path, params: request_body, headers: auth_header

              response_body = JSON.parse(response.body)

              expected = JSON.parse(
                Rails.root.join('modules', 'claims_api', 'spec', 'fixtures', 'v2', 'veterans',
                                'power_of_attorney', 'request_representative',
                                'expected_response_without_claimant.json').read
              )
              expected['data']['id'] = response_body['data']['id']

              expect(response).to have_http_status(:created)
              expect(response_body).to eq(expected)
            end
          end

          it 'does call the Orchestrator' do
            mock_ccg(scopes) do |auth_header|
              expect_any_instance_of(ClaimsApi::PowerOfAttorneyRequestService::Orchestrator)
                .to receive(:submit_request).and_return(orchestrator_res)

              post request_path, params: request_body, headers: auth_header
            end
          end

          it 'has Location in the response header' do
            mock_ccg(scopes) do |auth_header|
              expect_any_instance_of(ClaimsApi::PowerOfAttorneyRequestService::Orchestrator)
                .to receive(:submit_request).and_return(orchestrator_res)

              post request_path, params: request_body, headers: auth_header

              expect(response.headers).to have_key('Location')
            end
          end

          it 'persists a PowerOfAttorneyRequest record with the expected attributes' do
            mock_ccg(scopes) do |auth_header|
              allow_any_instance_of(ClaimsApi::PowerOfAttorneyRequestService::Orchestrator)
                .to receive(:submit_request).and_return(orchestrator_res)

              expect { post request_path, params: request_body, headers: auth_header }
                .to change(ClaimsApi::PowerOfAttorneyRequest, :count).by(1)

              poa_request = ClaimsApi::PowerOfAttorneyRequest.last
              expect(poa_request.proc_id).to eq(orchestrator_res['procId'])
              expect(poa_request.veteran_icn).to eq(veteran_id)
              expect(poa_request.poa_code).to eq('067')
            end
          end

          context 'when the orchestrator response includes metadata' do
            let(:orchestrator_res_with_meta) do
              orchestrator_res.merge(
                'meta' => {
                  'veteran' => {
                    'vnp_mail_id' => '151070',
                    'vnp_email_id' => '151071',
                    'vnp_phone_id' => '107777',
                    'phone_data' => {
                      'areaCode' => '555',
                      'phoneNumber' => '5551234'
                    }
                  }
                }
              )
            end

            it 'persists the metadata from the BGS response to the record' do
              mock_ccg(scopes) do |auth_header|
                allow_any_instance_of(ClaimsApi::PowerOfAttorneyRequestService::Orchestrator)
                  .to receive(:submit_request).and_return(orchestrator_res_with_meta)

                post request_path, params: request_body, headers: auth_header

                poa_request = ClaimsApi::PowerOfAttorneyRequest.last
                expect(poa_request.metadata).to eq(orchestrator_res_with_meta['meta'])
              end
            end
          end

          context 'when metadata validation fails while persisting the request' do
            let(:orchestrator_res_with_invalid_meta) do
              orchestrator_res.merge(
                'meta' => {
                  'veteran' => {
                    'unexpected_field' => 'not allowed'
                  }
                }
              )
            end

            it 'returns a generic 422 without exposing schema-internal field paths' do
              mock_ccg(scopes) do |auth_header|
                allow_any_instance_of(ClaimsApi::PowerOfAttorneyRequestService::Orchestrator)
                  .to receive(:submit_request).and_return(orchestrator_res_with_invalid_meta)

                post request_path, params: request_body, headers: auth_header

                response_body = JSON.parse(response.body)['errors'][0]

                expect(response).to have_http_status(:unprocessable_content)
                expect(response_body['detail']).to eq(
                  'Unable to process Power of Attorney request due to internal validation error.'
                )
              end
            end
          end
        end

        context 'lighthouse_claims_v2_poa_requests_skip_bgs enabled' do
          before do
            allow(Flipper).to receive(:enabled?).with(:lighthouse_claims_v2_poa_requests_skip_bgs).and_return(true)
          end

          let(:request_body) do
            Rails.root.join('modules', 'claims_api', 'spec', 'fixtures', 'v2', 'veterans',
                            'power_of_attorney', 'request_representative', 'valid_no_claimant.json').read
          end

          it 'returns the expected values from the blueprinter' do
            mock_ccg(scopes) do |auth_header|
              post request_path, params: request_body, headers: auth_header

              response_body = JSON.parse(response.body)

              expected = JSON.parse(
                Rails.root.join('modules', 'claims_api', 'spec', 'fixtures', 'v2', 'veterans',
                                'power_of_attorney', 'request_representative',
                                'expected_response_without_claimant.json').read
              )
              expected['data']['id'] = response_body['data']['id']

              expect(response).to have_http_status(:created)
              expect(response_body).to eq(expected)
            end
          end

          it 'does not call the Orchestrator' do
            mock_ccg(scopes) do |auth_header|
              expect_any_instance_of(ClaimsApi::PowerOfAttorneyRequestService::Orchestrator)
                .not_to receive(:submit_request)

              post request_path, params: request_body, headers: auth_header
            end
          end
        end
      end
    end

    context 'when the token is not valid' do
      it 'returns a 401' do
        post request_path, headers: { 'Authorization' => 'Bearer HelloWorld' }

        expect(response).to have_http_status(:unauthorized)
      end
    end
  end
end
