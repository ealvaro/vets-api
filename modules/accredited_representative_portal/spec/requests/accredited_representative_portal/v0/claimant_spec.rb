# frozen_string_literal: true

require_relative '../../../rails_helper'

# Ensure the top-level constant exists at file load time for verified doubles in CI.
IcnTemporaryIdentifier = AccreditedRepresentativePortal::IcnTemporaryIdentifier unless defined?(IcnTemporaryIdentifier)

RSpec.describe AccreditedRepresentativePortal::V0::ClaimantController, type: :request do
  before do
    login_as(test_user)
    travel_to(time)
    allow_any_instance_of(Auth::ClientCredentials::Service).to receive(:get_token).and_return('fake_access_token')

    allow_any_instance_of(AccreditedRepresentativePortal::PowerOfAttorneyHolderMemberships)
      .to receive(:empty?)
      .and_return(false)

    allow_any_instance_of(AccreditedRepresentativePortal::PowerOfAttorneyHolderMemberships)
      .to receive(:power_of_attorney_holders)
      .and_return([
                    AccreditedRepresentativePortal::PowerOfAttorneyHolder.new(
                      type: AccreditedRepresentativePortal::PowerOfAttorneyHolder::Types::VETERAN_SERVICE_ORGANIZATION,
                      poa_code:,
                      name: 'Test VSO',
                      can_accept_digital_poa_requests: true,
                      acceptance_mode: 'any_request'
                    )
                  ])

    allow_any_instance_of(AccreditedRepresentativePortal::PowerOfAttorneyHolderMemberships)
      .to receive(:registration_numbers)
      .and_return([representative.representative_id])
  end

  let!(:poa_code) { '067' }
  let!(:other_poa_code) { 'z99' }

  let!(:test_user) do
    create(:representative_user, email: 'test@va.gov', icn: '123498767V234859', all_emails: ['test@va.gov'])
  end

  let!(:representative) do
    create(:representative,
           :vso,
           email: test_user.email,
           representative_id: Faker::Number.unique.number(digits: 6),
           poa_codes: [poa_code])
  end

  let!(:vso) { create(:organization, poa: poa_code, can_accept_digital_poa_requests: true) }
  let!(:other_vso) { create(:organization, poa: other_poa_code, can_accept_digital_poa_requests: true) }

  let(:claimant) { create(:user_account, icn: '1008714701V416111') }
  let!(:poa_request) do
    create(:power_of_attorney_request, :with_veteran_claimant, poa_code:, accredited_individual: representative,
                                                               accredited_organization: vso, claimant:)
  end
  let!(:other_poa_request) { create(:power_of_attorney_request, claimant:, poa_code: other_poa_code) }

  let(:time) { '2024-12-21T04:45:37.000Z' }
  let(:time_plus_one_day) { '2024-12-22T04:45:37.000Z' }

  let(:monitoring) { instance_double(AccreditedRepresentativePortal::Monitoring) }

  describe 'GET /accredited_representative_portal/v0/claimant/search' do
    before do
      allow(AccreditedRepresentativePortal::Monitoring).to receive(:new).and_return(monitoring)
      allow(monitoring).to receive(:track_count)
    end

    context 'when providing incomplete search params' do
      it 'returns a 400 error' do
        post('/accredited_representative_portal/v0/claimant/search', params: {
               first_name: 'John', last_name: 'Smith', dob: '1980-01-01', ssn: ''
             })
        expect(response).to have_http_status(:bad_request)
      end
    end

    context 'when providing complete search params' do
      context 'mpi returns no records' do
        it 'returns nil' do
          VCR.use_cassette('mpi/find_candidate/icn_not_found') do
            post('/accredited_representative_portal/v0/claimant/search', params: {
                   first_name: 'John', last_name: 'Smith', dob: '1980-01-01', ssn: '666-66-6666'
                 })
            expect(response).to have_http_status(:ok)
            expect(parsed_response.fetch('data')).to be_nil
          end
        end

        it 'tracks attempts and no claimant found in Datadog' do
          expect(monitoring).to receive(:track_count).with('ar.unique_session.count')
          expect(monitoring).to receive(:track_count).with(
            described_class::SEARCH_ATTEMPT_METRIC,
            tags: ['org_resolve:failed']
          )
          expect(monitoring).to receive(:track_count).with(
            described_class::SEARCH_NO_CLAIMANT_FOUND_METRIC,
            tags: ['org_resolve:failed']
          )

          VCR.use_cassette('mpi/find_candidate/icn_not_found') do
            post('/accredited_representative_portal/v0/claimant/search', params: {
                   first_name: 'John',
                   last_name: 'Smith',
                   dob: '1980-01-01',
                   ssn: '867-53-0909'
                 })
          end
        end
      end

      it 'returns only matching claimant' do
        VCR.use_cassette('mpi/find_candidate/valid_icn_full') do
          VCR.use_cassette(
            'accredited_representative_portal/requests/accredited_representative_portal/v0/claimant_spec/' \
            'lighthouse/benefits_claims/200_response'
          ) do
            post('/accredited_representative_portal/v0/claimant/search', params: {
                   first_name: 'John', last_name: 'Smith', dob: '1980-01-01', ssn: '666-66-6666'
                 })
          end
        end
        expect(response).to have_http_status(:ok)
        expect(parsed_response.dig('data', 'poaRequests').map { |poa| poa['id'] }).to eq([poa_request.id])
        expect(parsed_response.dig('data', 'hasPendingPoaRequest')).to be true
      end

      it 'tracks attempts and success in Datadog' do
        expect(monitoring).to receive(:track_count).with('ar.unique_session.count')
        expect(monitoring).to receive(:track_count).with(
          described_class::SEARCH_ATTEMPT_METRIC,
          tags: ['org_resolve:failed']
        )
        expect(monitoring).to receive(:track_count).with(
          described_class::SEARCH_SUCCESS_METRIC,
          tags: ['org_resolve:failed']
        )

        VCR.use_cassette('mpi/find_candidate/valid_icn_full') do
          VCR.use_cassette(
            'accredited_representative_portal/requests/accredited_representative_portal/v0/claimant_spec/' \
            'lighthouse/benefits_claims/200_response'
          ) do
            post('/accredited_representative_portal/v0/claimant/search', params: {
                   first_name: 'John',
                   last_name: 'Smith',
                   dob: '1980-01-01',
                   ssn: '867-53-0909'
                 })
          end
        end

        expect(response).to have_http_status(:ok)
      end

      context 'there are multiple PoA request attempts' do
        let!(:other_poa_request) do
          create(:power_of_attorney_request,
                 :with_veteran_claimant,
                 :with_pending_form_submission,
                 poa_code:, accredited_individual: representative,
                 accredited_organization: vso, claimant:, created_at: 1.day.ago)
        end
        let!(:accepted_poa_request) do
          create(:power_of_attorney_request,
                 :with_veteran_claimant,
                 :with_acceptance,
                 poa_code:, accredited_individual: representative,
                 accredited_organization: vso, claimant:, created_at: 2.days.ago)
        end
        let!(:declined_poa_request) do
          create(:power_of_attorney_request,
                 :with_veteran_claimant,
                 :with_declination,
                 poa_code:, accredited_individual: representative,
                 accredited_organization: vso, claimant:, created_at: 3.days.ago)
        end

        it 'orders poa requests with pending first, then by date' do
          VCR.use_cassette('mpi/find_candidate/valid_icn_full') do
            VCR.use_cassette(
              'accredited_representative_portal/requests/accredited_representative_portal/v0/claimant_spec/' \
              'lighthouse/benefits_claims/200_response'
            ) do
              post('/accredited_representative_portal/v0/claimant/search', params: {
                     first_name: 'John', last_name: 'Smith', dob: '1980-01-01', ssn: '666-66-6666'
                   })
            end
          end
          expect(response).to have_http_status(:ok)
          expect(parsed_response.dig('data', 'poaRequests').map { |poa| poa['id'] }).to eq(
            [
              poa_request.id,
              other_poa_request.id,
              accepted_poa_request.id,
              declined_poa_request.id
            ]
          )
        end
      end

      context 'when there is a withdrawn poa request' do
        let!(:withdrawn_poa_request) do
          create(:power_of_attorney_request, :with_veteran_claimant,
                 poa_code:, accredited_individual: representative,
                 accredited_organization: vso, claimant:).tap do |req|
            req.mark_replaced!(create(:power_of_attorney_request))
          end
        end

        it 'does not return the withdrawn poa request' do
          VCR.use_cassette('mpi/find_candidate/valid_icn_full') do
            VCR.use_cassette(
              'accredited_representative_portal/requests/accredited_representative_portal/v0/claimant_spec/' \
              'lighthouse/benefits_claims/200_response'
            ) do
              post('/accredited_representative_portal/v0/claimant/search', params: {
                     first_name: 'John', last_name: 'Smith', dob: '1980-01-01', ssn: '666-66-6666'
                   })
            end
          end
          expect(response).to have_http_status(:ok)
          returned_ids = parsed_response.dig('data', 'poaRequests').map { |poa| poa['id'] }
          expect(returned_ids).not_to include(withdrawn_poa_request.id)
        end
      end

      # A rep who has only resolved (declined) requests for a claimant and no established
      # POA must not be able to reveal the claimant via search.
      context 'when the only request is declined and there is no established POA' do
        let!(:poa_request) do
          create(:power_of_attorney_request, :with_veteran_claimant, :with_declination,
                 poa_code:, accredited_individual: representative,
                 accredited_organization: vso, claimant:)
        end
        let!(:other_poa_request) { nil }

        before do
          # No established POA for the claimant, so claimant_representative is nil.
          allow_any_instance_of(BenefitsClaims::Service)
            .to receive(:get_power_of_attorney).and_return({ 'data' => {} })
        end

        it 'returns nil and does not expose claimant details' do
          VCR.use_cassette('mpi/find_candidate/valid_icn_full') do
            post('/accredited_representative_portal/v0/claimant/search', params: {
                   first_name: 'John', last_name: 'Smith', dob: '1980-01-01', ssn: '666-66-6666'
                 })
          end
          expect(response).to have_http_status(:ok)
          expect(parsed_response.fetch('data')).to be_nil
        end
      end
    end
  end

  describe 'GET /accredited_representative_portal/v0/claimant/:id' do
    let(:json_headers) { { 'ACCEPT' => 'application/json' } }
    let(:identifier_id) { SecureRandom.uuid }
    let(:benefit_type) { 'compensation' }

    let(:path) { "/accredited_representative_portal/v0/claimant/#{identifier_id}" }

    let(:mpi_profile) do
      build(
        :mpi_profile,
        icn: '1008714701V416111',
        given_names: ['John'],
        family_name: 'Smith',
        birth_date: '1980-01-01',
        ssn: '666-66-6666',
        home_phone: '555-555-5555',
        address: OpenStruct.new(
          street: '123 Main St',
          street2: 'Apt 4',
          city: 'Springfield',
          state: 'VA',
          postal_code: '12345'
        )
      )
    end

    let(:icn) { mpi_profile.icn }
    let(:mpi_profile_response) { create(:find_profile_response, profile: mpi_profile) }

    let(:mpi_service) { instance_double(MPI::Service) }
    let(:claimant_details_service) { instance_double(AccreditedRepresentativePortal::ClaimantDetailsService) }

    let(:claimant_representative) do
      instance_double(AccreditedRepresentativePortal::ClaimantRepresentative,
                      power_of_attorney_holder: OpenStruct.new(name: 'Space Force Cadets'))
    end

    before do
      stub_const('IcnTemporaryIdentifier', AccreditedRepresentativePortal::IcnTemporaryIdentifier)

      allow(IcnTemporaryIdentifier).to receive(:lookup_icn).with(identifier_id).and_return(icn)

      # Policy: allow happy path POA check
      allow(AccreditedRepresentativePortal::ClaimantRepresentative).to receive(:find)
        .and_return(claimant_representative)

      allow(MPI::Service).to receive(:new).and_return(mpi_service)
      allow(mpi_service).to receive(:find_profile_by_identifier).and_return(mpi_profile_response)

      allow(AccreditedRepresentativePortal::ClaimantDetailsService).to receive(:new).with(
        icn:,
        representative_name: 'Space Force Cadets',
        benefit_type_param: benefit_type,
        power_of_attorney_requests: kind_of(ActiveRecord::Relation),
        is_representative: true
      ).and_return(claimant_details_service)

      allow(claimant_details_service).to receive(:call).and_return(
        {
          data: {
            first_name: 'John',
            last_name: 'Smith',
            birth_date: '1980-01-01',
            ssn: '6666', # NEW: masked
            poa_requests: [],
            is_representative: true,
            itf: [{ 'status' => 'ok' }]
          }
        }
      )
      allow(AccreditedRepresentativePortal::Monitoring).to receive(:new).and_return monitoring
      allow(monitoring).to receive(:track_count)
    end

    context 'when benefitType is invalid' do
      let(:benefit_type) { 'burial' }

      it 'returns 422 unprocessable entity' do
        get(path, params: { benefitType: benefit_type }, headers: json_headers)
        expect(response).to have_http_status(:unprocessable_content)
      end
    end

    context 'when the claimant exists in MPI' do
      it 'returns claimant profile fields (SSN masked to last 4)' do
        get(path, params: { benefitType: benefit_type }, headers: json_headers)

        expect(response).to have_http_status(:ok)
        data = parsed_response.fetch('data')
        expect(data['first_name']).to eq('John')
        expect(data['last_name']).to eq('Smith')
        expect(data['birth_date']).to eq('1980-01-01')
        expect(data['ssn']).to eq('6666')
      end

      it 'tracks attempts and success in Datadog' do
        expect(monitoring).to receive(:track_count).with('ar.unique_session.count')
        expect(monitoring).to receive(:track_count).with(
          described_class::SHOW_ATTEMPT_METRIC, tags: ['org_resolve:failed']
        )
        expect(monitoring).to receive(:track_count).with(
          described_class::SHOW_SUCCESS_METRIC, tags: ['org_resolve:failed']
        )
        get(path, params: { benefitType: benefit_type }, headers: json_headers)

        expect(response).to have_http_status(:ok)
      end

      it 'includes itf payload' do
        get(path, params: { benefitType: benefit_type }, headers: json_headers)

        expect(response).to have_http_status(:ok)
        expect(parsed_response.dig('data', 'itf')).to be_present
      end

      it 'includes pending poa requests in the payload' do
        allow(claimant_details_service).to receive(:call).and_return(
          {
            data: {
              first_name: 'John',
              last_name: 'Smith',
              birth_date: '1980-01-01',
              ssn: '6666',
              poa_requests: [
                {
                  id: poa_request.id,
                  resolution: nil
                }
              ],
              is_representative: true,
              itf: [{ 'status' => 'ok' }]
            }
          }
        )

        get(path, params: { benefitType: benefit_type }, headers: json_headers)

        expect(response).to have_http_status(:ok)
        expect(parsed_response.dig('data', 'poa_requests')).to eq(
          [
            {
              'id' => poa_request.id,
              'resolution' => nil
            }
          ]
        )
        expect(parsed_response.dig('data', 'is_representative')).to be true
      end
    end

    context 'when itf lookup fails' do
      before do
        allow(claimant_details_service).to receive(:call).and_return(
          {
            data: {
              first_name: 'John',
              last_name: 'Smith',
              birth_date: '1980-01-01',
              ssn: '6666',
              itf: []
            }
          }
        )
      end

      it 'still returns claimant profile fields and itf is an empty array' do
        get(path, params: { benefitType: benefit_type }, headers: json_headers)

        expect(response).to have_http_status(:ok)
        data = parsed_response.fetch('data')
        expect(data['first_name']).to eq('John')
        expect(data['last_name']).to eq('Smith')
        expect(data['birth_date']).to eq('1980-01-01')
        expect(data['ssn']).to eq('6666')
        expect(data['itf']).to eq([])
      end
    end

    context 'when rep does not have POA for claimant' do
      before do
        allow(AccreditedRepresentativePortal::ClaimantRepresentative)
          .to receive(:find)
          .and_raise(AccreditedRepresentativePortal::ClaimantRepresentative::Finder::Error)
      end

      it 'returns 403 forbidden' do
        get(path, params: { benefitType: benefit_type }, headers: json_headers)
        expect(response).to have_http_status(:forbidden)
      end
    end

    context 'when MPI returns no profile' do
      before do
        allow(mpi_service).to receive(:find_profile_by_identifier).and_return(OpenStruct.new(profile: nil))
        allow(claimant_details_service).to receive(:call)
          .and_raise(Common::Exceptions::RecordNotFound, 'Claimant not found')
      end

      it 'returns 404 not found' do
        get(path, params: { benefitType: benefit_type }, headers: json_headers)
        expect(response).to have_http_status(:not_found)
      end

      it 'tracks attempts and errors in Datadog' do
        expect(monitoring).to receive(:track_count).with('ar.unique_session.count')
        expect(monitoring).to receive(:track_count).with(
          described_class::SHOW_ATTEMPT_METRIC, tags: ['org_resolve:failed']
        )
        expect(monitoring).to receive(:track_count).with(
          described_class::SHOW_ERROR_METRIC, tags: ['org_resolve:failed', 'reason:RecordNotFound']
        )
        get(path, params: { benefitType: benefit_type }, headers: json_headers)
      end
    end

    context 'when the temporary identifier does not exist' do
      before do
        allow(IcnTemporaryIdentifier).to receive(:lookup_icn).with(identifier_id).and_raise(ActiveRecord::RecordNotFound)
      end

      it 'returns 404 not found' do
        get(path, params: { benefitType: benefit_type }, headers: json_headers)
        expect(response).to have_http_status(:not_found)
      end

      it 'tracks attempts and errors in Datadog' do
        expect(monitoring).to receive(:track_count).with('ar.unique_session.count')
        expect(monitoring).to receive(:track_count).with(
          described_class::SHOW_ATTEMPT_METRIC, tags: ['org_resolve:failed']
        )
        expect(monitoring).to receive(:track_count).with(
          described_class::SHOW_ERROR_METRIC, tags: ['org_resolve:failed', 'reason:RecordNotFound']
        )
        get(path, params: { benefitType: benefit_type }, headers: json_headers)
      end
    end
  end
end
