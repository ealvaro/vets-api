# frozen_string_literal: true

require_relative '../../../rails_helper'

RSpec.describe AccreditedRepresentativePortal::V0::ClaimantClaimSubmissionsController, type: :request do
  before do
    login_as(representative_user)
    allow_any_instance_of(Auth::ClientCredentials::Service).to receive(:get_token).and_return('fake_access_token')
    allow(Flipper).to receive(:enabled?)
      .with(:accredited_representative_portal_individual_accept_backend)
      .and_return(false)

    # This removes: SHRINE WARNING: Error occurred when attempting to extract image dimensions:
    # #<FastImage::UnknownImageType: FastImage::UnknownImageType>
    allow(FastImage).to receive(:size).and_wrap_original do |original, file|
      if file.respond_to?(:path) && file.path.end_with?('.pdf')
        nil
      else
        original.call(file)
      end
    end
  end

  describe 'GET /accredited_representative_portal/v0/claimant_claim_submissions/:id' do
    let!(:poa_code) { '067' }
    let(:representative_user) do
      create(:representative_user, email: 'test@va.gov', icn: '123498767V234859', all_emails: ['test@va.gov'])
    end
    let!(:representative) do
      create(:representative,
             :vso,
             email: representative_user.email,
             representative_id: '357458',
             poa_codes: [poa_code])
    end
    let!(:vso) { create(:organization, poa: poa_code, can_accept_digital_poa_requests: false) }
    let!(:icn_temporary_identifier) do
      AccreditedRepresentativePortal::IcnTemporaryIdentifier.create(icn: '1012832013V553700')
    end
    let(:search_identifier) { icn_temporary_identifier.id }
    let(:search_identifier_b) { SecureRandom.uuid }

    # Default two that should be visible to the rep.
    # Make them older so the sorting test can deterministically place newer records on page 1.
    let!(:saved_claim_claimant_representative_a) do
      create(:saved_claim_claimant_representative, :dependent, created_at: 10.days.ago, claimant_id: search_identifier)
    end
    let!(:saved_claim_claimant_representative_b) do
      create(:saved_claim_claimant_representative, :veteran, created_at: 9.days.ago, claimant_id: search_identifier)
    end

    # different PoA code → should be filtered out
    let!(:saved_claim_claimant_representative_c) do
      create(:saved_claim_claimant_representative, :dependent, power_of_attorney_holder_poa_code: '002')
    end
    # different claimant → should be filtered out
    let!(:saved_claim_claimant_representative_d) do
      create(:saved_claim_claimant_representative, :dependent, claimant_id: search_identifier_b)
    end

    before do
      allow(Flipper).to receive(:enabled?).with(:accredited_representative_portal_claimant_details)
                                          .and_return(true)
    end

    around do |example|
      VCR.use_cassette('lighthouse/benefits_claims/power_of_attorney/200_response') do
        example.run
      end
    end

    describe 'GET /accredited_representative_portal/v0/claims_submissions' do
      context 'claimant identifier is specified' do
        before do
          saved_claim_claimant_representative_a.saved_claim.update(
            form: {
              'veteran' =>
                { 'name' => { 'first' => 'Maurice', 'last' => 'Murphy' },
                  'ssn' => '796265005',
                  'dateOfBirth' => '1973-05-26',
                  'postalCode' => '12345' },
              'dependent' =>
                { 'name' => { 'first' => 'Claim', 'last' => 'Jane' },
                  'ssn' => '796465445',
                  'dateOfBirth' => '1993-02-26',
                  'postalCode' => '12345' }
            }.to_json
          )
          saved_claim_claimant_representative_b.saved_claim.update(
            form: {
              'veteran' =>
                { 'name' => { 'first' => 'Maurice', 'last' => 'Murphy' },
                  'ssn' => '796265005',
                  'dateOfBirth' => '1973-05-26',
                  'postalCode' => '12345' }
            }.to_json
          )
        end

        context 'claimant details feature flag is enabled' do
          context 'rep does not have any valid PoA codes' do
            let!(:representative) do
              create(:representative,
                     :vso,
                     email: representative_user.email,
                     representative_id: '357458',
                     poa_codes: ['11'])
            end

            it 'returns 403' do
              get "/accredited_representative_portal/v0/claimant_claim_submissions/#{search_identifier}"
              expect(response).to have_http_status(:forbidden)
            end
          end

          context 'a valid claimant identifier is supplied' do
            it 'filters results to that claimant' do
              VCR.use_cassette('mpi/find_candidate/find_profile_with_identifier') do
                get "/accredited_representative_portal/v0/claimant_claim_submissions/#{search_identifier}"
                expect(response).to have_http_status(:ok)

                expect(parsed_response).to eq(
                  {
                    'data' => [
                      {
                        'claimantId' => saved_claim_claimant_representative_a.claimant_id,
                        'submittedDate' => saved_claim_claimant_representative_a.created_at.to_date.iso8601,
                        'firstName' => 'Claim',
                        'lastName' => 'Jane',
                        'formType' => '21-686c',
                        'benefitType' => nil,
                        'packet' => false,
                        'confirmationNumber' =>
                          saved_claim_claimant_representative_a.saved_claim
                            .latest_submission_attempt.benefits_intake_uuid,
                        'vbmsStatus' => 'awaiting_receipt',
                        'vbmsReceivedDate' => nil,
                        'id' => saved_claim_claimant_representative_a.id
                      },
                      {
                        'claimantId' => saved_claim_claimant_representative_b.claimant_id,
                        'submittedDate' => saved_claim_claimant_representative_b.created_at.to_date.iso8601,
                        'firstName' => 'Maurice',
                        'lastName' => 'Murphy',
                        'formType' => '21-686c',
                        'benefitType' => nil,
                        'packet' => false,
                        'confirmationNumber' =>
                          saved_claim_claimant_representative_b.saved_claim
                            .latest_submission_attempt.benefits_intake_uuid,
                        'vbmsStatus' => 'awaiting_receipt',
                        'vbmsReceivedDate' => nil,
                        'id' => saved_claim_claimant_representative_b.id
                      }
                    ],
                    'meta' => {
                      'page' => {
                        'number' => 1,
                        'size' => 10,
                        'total' => 2,
                        'totalPages' => 1
                      }
                    },
                    'claimant' => {
                      'firstName' => 'Maurice',
                      'lastName' => 'Murphy'
                    }
                  }
                )
              end
            end
          end

          context 'a known but invalid claimant identifier is supplied' do
            it 'results in a 404 error' do
              VCR.use_cassette('mpi/find_candidate/icn_not_found') do
                get "/accredited_representative_portal/v0/claimant_claim_submissions/#{search_identifier}"
                expect(response).to have_http_status(:not_found)
              end
            end
          end

          context 'an invalid claimant identifier is supplied' do
            it 'results in a 404 error' do
              get '/accredited_representative_portal/v0/claimant_claim_submissions/bogus'
              expect(response).to have_http_status(:not_found)
            end
          end
        end
      end

      context 'claimant details feature flag is off' do
        before do
          allow(Flipper).to receive(:enabled?).with(:accredited_representative_portal_claimant_details)
                                              .and_return(false)
        end

        it 'returns a 400 error' do
          VCR.use_cassette('mpi/find_candidate/find_profile_with_identifier') do
            get "/accredited_representative_portal/v0/claimant_claim_submissions/#{search_identifier}"
            expect(response).to have_http_status(:bad_request)
          end
        end
      end
    end

    describe 'sorting and pagination plumbing' do
      let!(:older) do
        create(:saved_claim_claimant_representative, created_at: 3.days.ago, claimant_id: search_identifier)
      end
      let!(:newest) do
        create(:saved_claim_claimant_representative, created_at: 1.day.ago, claimant_id: search_identifier)
      end

      before do
        allow(AccreditedRepresentativePortal::SubmissionsService::ParamsSchema)
          .to receive(:validate_and_normalize!)
          .and_return({
                        sort: { by: 'created_at', order: 'desc' },
                        page: { number: 1, size: 2 }
                      })
      end

      around do |example|
        VCR.use_cassette('mpi/find_candidate/find_profile_with_identifier') do
          example.run
        end
      end

      it 'returns results ordered by submittedDate desc and paginates' do
        get "/accredited_representative_portal/v0/claimant_claim_submissions/#{search_identifier}"
        expect(response).to have_http_status(:ok)

        body = parsed_response
        expect(body.dig('meta', 'page', 'number')).to eq(1)
        expect(body.dig('meta', 'page', 'size')).to eq(2)
        expect(body['data'].size).to eq(2)

        dates = body['data'].map { |h| Date.iso8601(h['submittedDate']) }
        expect(dates).to eq(dates.sort.reverse) # sorted desc
        expect(dates).to include(newest.created_at.to_date) # newest included on page 1
      end
    end

    describe 'invalid params' do
      before do
        allow(AccreditedRepresentativePortal::SubmissionsService::ParamsSchema)
          .to receive(:validate_and_normalize!)
          .and_raise(Common::Exceptions::ParameterMissing.new('page.size'))
      end

      around do |example|
        VCR.use_cassette('mpi/find_candidate/find_profile_with_identifier') do
          example.run
        end
      end

      it 'returns 400 (or 422) when params schema validation fails' do
        get "/accredited_representative_portal/v0/claimant_claim_submissions/#{search_identifier}",
            params: { page: { size: 'not-a-number' } }
        expect(response.status).to be_in([400, 422])
      end
    end

    describe 'defaults (no sort/page params)' do
      before do
        allow(AccreditedRepresentativePortal::SubmissionsService::ParamsSchema)
          .to receive(:validate_and_normalize!)
          .and_return({})
      end

      around do |example|
        VCR.use_cassette('mpi/find_candidate/find_profile_with_identifier') do
          example.run
        end
      end

      it 'uses default pagination and does not error' do
        get "/accredited_representative_portal/v0/claimant_claim_submissions/#{search_identifier}"
        expect(response).to have_http_status(:ok)

        meta_page = parsed_response.dig('meta', 'page')
        expect(meta_page['number']).to eq(1)
        expect(meta_page['size']).to eq(30)
      end
    end
  end
end
