# frozen_string_literal: true

RSpec.shared_examples 'returns 422 for veteran with duplicate BIRLS IDs' do
  # Expects: let(:submit_path), let(:submit_scopes), let(:submit_params)
  it 'returns a 422' do
    mock_ccg(submit_scopes) do |auth_header|
      allow_any_instance_of(MPIData).to receive(:birls_ids).and_return(%w[111222333 444555666])
      post submit_path, params: submit_params, headers: auth_header
      expect(response).to have_http_status(:unprocessable_content)
      expect(JSON.parse(response.body)['errors'][0]['detail']).to include('multiple active BIRLS file numbers')
    end
  end
end

RSpec.shared_examples 'returns 422 for claimant with duplicate participant IDs' do
  # Expects: let(:submit_path), let(:submit_scopes), let(:submit_params)
  # Optional: let(:vcr_cassette) — override to wrap the request in a VCR cassette
  let(:vcr_cassette) { nil }

  before do
    allow(Flipper).to receive(:enabled?).with(:lighthouse_claims_api_poa_dependent_claimants).and_return(true)
    allow_any_instance_of(ClaimsApi::DependentClaimantVerificationService)
      .to receive(:validate_poa_code_exists!).and_return(nil)
    allow_any_instance_of(ClaimsApi::DependentClaimantVerificationService)
      .to receive(:validate_dependent_by_participant_id!).and_call_original
    allow_any_instance_of(ClaimsApi::PersonWebService)
      .to receive(:find_dependents_by_ptcpnt_id)
      .and_return({ number_of_records: 1,
                    dependent: [{ first_nm: 'Jane', last_nm: 'Doe', ptcpnt_id: '123',
                                  ssn_nbr: '123456789', brthdy_dt: '1990-01-01' }] })
    mpi_profile = build(:mpi_profile, participant_ids: %w[600052700 600099999])
    allow_any_instance_of(MPI::Service)
      .to receive(:find_profile_by_attributes)
      .and_return(build(:find_profile_response, profile: mpi_profile))
  end

  it 'returns a 422' do
    run = lambda do
      mock_ccg(submit_scopes) do |auth_header|
        post submit_path, params: submit_params, headers: auth_header
        expect(response).to have_http_status(:unprocessable_content)
        expect(JSON.parse(response.body)['errors'][0]['detail']).to include('multiple active Participant IDs')
      end
    end
    vcr_cassette ? VCR.use_cassette(vcr_cassette, &run) : run.call
  end
end
