# frozen_string_literal: true

RSpec.shared_examples 'dependent claimant headers' do
  # Expects the including context to define:
  #   let(:appoint_path)  — the endpoint path to POST to
  #   let(:scopes)        — CCG scopes
  #   let(:request_body)  — JSON string of a valid form submission
  #   let(:user_profile)  — MPI::Responses::FindProfileResponse with dependent profile data
  #   let(:claimant_data) — hash with claimantId, address, and relationship
  #
  # And a before block that stubs:
  #   BaseController#user_profile, BaseController#current_poa,
  #   DependentClaimantVerificationService#validate_poa_code_exists!,
  #   DependentClaimantVerificationService#validate_dependent_by_participant_id!

  context 'when the lighthouse_claims_api_poa_dependent_claimants feature is enabled' do
    before do
      allow_any_instance_of(ClaimsApi::V2::Veterans::PowerOfAttorney::BaseController)
        .to receive(:disable_jobs?).and_return(false)
      allow(Flipper).to receive(:enabled?).with(:lighthouse_claims_api_poa_dependent_claimants)
                                          .and_return(true)
      mock_file_number_check
    end

    context 'and the request includes a claimant' do
      it 'adds dependent values with correct data to the auth_headers' do
        VCR.use_cassette('claims_api/mpi/find_candidate/valid_icn_full') do
          mock_ccg(scopes) do |auth_header|
            json = JSON.parse(request_body)
            json['data']['attributes']['claimant'] = claimant_data.deep_stringify_keys
            body = json.to_json

            post appoint_path, params: body, headers: auth_header

            poa_id = JSON.parse(response.body)['data']['id']
            poa = ClaimsApi::PowerOfAttorney.find(poa_id)
            dependent = poa.auth_headers['dependent']

            expect(dependent).to be_present
            expect(dependent['participant_id']).to eq(user_profile.profile.participant_id)
            expect(dependent['ssn']).to eq(user_profile.profile.ssn)
            expect(dependent['first_name']).to eq(user_profile.profile.given_names&.first)
            expect(dependent['last_name']).to eq(user_profile.profile.family_name)
          end
        end
      end

      it "does not add dependent values to the auth_headers if relationship is 'Self'" do
        VCR.use_cassette('claims_api/mpi/find_candidate/valid_icn_full') do
          mock_ccg(scopes) do |auth_header|
            json = JSON.parse(request_body)
            stringified_claimant = claimant_data.deep_stringify_keys
            stringified_claimant['relationship'] = 'Self'
            json['data']['attributes']['claimant'] = stringified_claimant
            body = json.to_json

            post appoint_path, params: body, headers: auth_header

            poa_id = JSON.parse(response.body)['data']['id']
            poa = ClaimsApi::PowerOfAttorney.find(poa_id)
            expect(poa.auth_headers).not_to have_key('dependent')
          end
        end
      end
    end
  end

  context 'when the lighthouse_claims_api_poa_dependent_claimants feature is disabled' do
    before do
      allow(Flipper).to receive(:enabled?).with(:lighthouse_claims_api_poa_dependent_claimants)
                                          .and_return(false)
      mock_file_number_check
    end

    it 'does not add the dependent object to the auth_headers' do
      VCR.use_cassette('claims_api/mpi/find_candidate/valid_icn_full') do
        mock_ccg(scopes) do |auth_header|
          json = JSON.parse(request_body)
          json['data']['attributes']['claimant'] = claimant_data.deep_stringify_keys
          body = json.to_json

          post appoint_path, params: body, headers: auth_header

          poa_id = JSON.parse(response.body)['data']['id']
          poa = ClaimsApi::PowerOfAttorney.find(poa_id)
          expect(poa.auth_headers).not_to have_key('dependent')
        end
      end
    end
  end
end
