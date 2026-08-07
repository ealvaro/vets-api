# frozen_string_literal: true

require_relative '../../../rails_helper'
require_relative '../../../support/poa_holder_fixtures'

# Regression coverage for a bug where serializing power_of_attorney_form mutated
# PowerOfAttorneyForm#parsed_data (SSN redaction), causing dependentRelationshipEstablished
# to incorrectly return false for dependents.
RSpec.describe AccreditedRepresentativePortal::V0::PowerOfAttorneyRequestsController, type: :request do
  # Provides create_holder_registration / create_holder_organization and stubs
  # use_accredited_models? => true (the modern accredited-models path).
  include_context 'with accredited poa holders'

  let(:poa_code) { 'x23' }
  let(:registration_number) { '987654' }
  let(:dependent_participant_id) { '600849397' } # MILLY LOW in the dependents_valid cassette

  let(:test_user) do
    create(:representative_user, email: 'test@va.gov', icn: '123498767V234859', all_emails: ['test@va.gov'])
  end

  # Dependent claimant whose ICN matches ICN_REGEX (/\A\d{10}V\d{6}\z/) so the
  # dependent-side validation passes and the lookup proceeds to MPI/BGS.
  let(:claimant_user_account) { create(:user_account, icn: '1013469511V725621') }

  let(:poa_request) do
    create(:power_of_attorney_request, :with_dependent_claimant, poa_code:, claimant: claimant_user_account)
  end

  let(:mpi_service) { instance_double(MPI::Service) }
  let(:veteran_mpi_profile) { build(:mpi_profile) }
  let(:dependent_mpi_profile) { build(:mpi_profile, participant_id: dependent_participant_id) }

  before do
    login_as(test_user)

    allow(Flipper).to receive(:enabled?).and_call_original
    allow(Flipper).to receive(:enabled?)
      .with(:accredited_representative_portal_killswitch)
      .and_return(false)

    allow_any_instance_of(AccreditedRepresentativePortal::PowerOfAttorneyHolderMemberships)
      .to receive(:empty?).and_return(false)
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
      .to receive(:registration_numbers).and_return([registration_number])

    create_holder_registration(type: :vso, registration_number:, poa_codes: [poa_code], email: test_user.email)
    create_holder_organization(poa_code:, name: 'Test VSO', can_accept: true)

    # Stub the MPI boundary only. The veteran profile is looked up by attributes,
    # the dependent profile by ICN. The real DependentLookupService still runs.
    allow(MPI::Service).to receive(:new).and_return(mpi_service)
    allow(mpi_service)
      .to receive_messages({
                             find_profile_by_attributes: OpenStruct.new(profile: veteran_mpi_profile),
                             find_profile_by_identifier: OpenStruct.new(profile: dependent_mpi_profile)
                           })
  end

  describe 'GET /accredited_representative_portal/v0/power_of_attorney_requests/:id' do
    context 'when the claimant is a dependent' do
      it 'passes the full 9-digit veteran SSN to DependentLookupService (not the redacted value)' do
        allow(AccreditedRepresentativePortal::DependentLookupService).to receive(:new).and_call_original

        VCR.use_cassette('bgs/claimant_web_service/dependents_valid') do
          get("/accredited_representative_portal/v0/power_of_attorney_requests/#{poa_request.id}")
        end

        expect(response).to have_http_status(:ok)
        # Regression assertion: ensure we pass the full 9-digit SSN (not the redacted
        # last-4 value like '6789').
        expect(AccreditedRepresentativePortal::DependentLookupService).to have_received(:new)
          .with(veteran: hash_including(ssn: '123456789'))
      end

      it 'returns dependentRelationshipEstablished: true for a matching dependent' do
        VCR.use_cassette('bgs/claimant_web_service/dependents_valid') do
          get("/accredited_representative_portal/v0/power_of_attorney_requests/#{poa_request.id}")
        end

        expect(response).to have_http_status(:ok)
        # End-to-end proof: the dependent's participant ID matches a BGS
        # dependent record in this cassette, so the established flag should be true.
        expect(parsed_response['dependentRelationshipEstablished']).to be(true)
      end
    end
  end
end
